// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
import "hardhat/console.sol";

// Import chainlink/contracts framework dependencies
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

// Import local dependencies
import "./Order.sol";

/**
 * @title Delivery
 * @author Daniel Piassi
 * @notice A contract to store a delivery
 */
contract Delivery is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;
    /// @dev Enum to store the callback flag
    enum CallbackFlag {
        NONE,
        DELIVER_ORDER,
        CONFIRM_ORDER_RECEIPT
    }

    /// @dev State variables to store the last callback info
    struct OrderState {
        int32 curLat;
        int32 curLng;
        uint256 timestamp;
    }

    /// @dev State variables
    mapping(address => Order) public orders;
    address[] public orderAddresses;
    uint256 public ordersCount;
    address public lastOrder;
    int32 public deliveredDistanceThreshold = 400; // in meters

    /// @dev Chainlink External API Calls
    bytes32 private jobId;
    uint256 private fee;

    /// @dev Multiple params returned in a single oracle response
    mapping(address => OrderState) public ordersState;

    /// @dev Events
    event OrderCreated(address indexed orderAddress);
    event OrderDelivered(address indexed orderAddress);
    event OrderReceiptConfirmed(address indexed orderAddress);
    event RequestFulfilled(bytes32 indexed requestId, int256 rawData);

    /// @dev State variables to store the last callback info
    CallbackFlag private callbackFlag;
    address private lastCallerAddress;
    address private lastOrderAddress;

    /// @dev Modifiers
    modifier onlySender(address orderAddress) {
        assertIsOrder(orderAddress);
        Order order = orders[orderAddress];
        require(msg.sender == order.sender(), "You aren't the sender");
        _;
    }

    modifier onlyReceiver(address orderAddress) {
        assertIsOrder(orderAddress);
        Order order = orders[orderAddress];
        require(msg.sender == order.receiver(), "You aren't the receiver");
        _;
    }

    /**
     * @notice Initialize the link token and target oracle
     * @dev The oracle address must be an Operator contract for multiword response
     *
     * Sepolia Testnet details:
     * Oracle: 0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD (Chainlink DevRel)
     * jobId: fcf4140d696d44b687012232948bdd5d
     */
    constructor() ConfirmedOwner(msg.sender) {
        setChainlinkToken(0x779877A7B0D9E8603169DdbD7836e478b4624789);
        setChainlinkOracle(0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD);
        jobId = "fcf4140d696d44b687012232948bdd5d"; // int256
        fee = (1 * LINK_DIVISIBILITY) / 10; // 0,1 * 10**18 (Varies by network and job)
        callbackFlag = CallbackFlag.NONE;
    }

    /**
     * @notice Create a new Order object
     * @param _receiver The address of the receiver
     * @param _srcLat The latitude of the source location in microdegrees
     * @param _srcLng The longitude of the source location in microdegrees
     * @param _dstLat The latitude of the destination location in microdegrees
     * @param _dstLng The longitude of the destination location in microdegrees
     * @param _expectedTimeOfArrival The expected time of arrival (unix timestamp)
     * @return orderAddress The address of the created order
     */
    function createOrder(
        address _receiver,
        int32 _srcLat,
        int32 _srcLng,
        int32 _dstLat,
        int32 _dstLng,
        uint256 _expectedTimeOfArrival
    ) public returns (address orderAddress) {
        Order order = new Order(
            msg.sender,
            _receiver,
            _srcLat,
            _srcLng,
            _dstLat,
            _dstLng,
            _expectedTimeOfArrival
        );
        lastOrder = address(order);
        emit OrderCreated(lastOrder);
        orders[lastOrder] = order;
        orderAddresses.push(lastOrder);
        ordersCount++;
        return lastOrder;
    }

    /**
     * @notice We may change the distance threshold to consider the order as delivered
     * @param _deliveredDistanceThreshold The distance threshold to consider the order as delivered
     */
    function setDeliveredDistanceThreshold(
        int32 _deliveredDistanceThreshold
    ) public onlyOwner {
        deliveredDistanceThreshold = _deliveredDistanceThreshold;
    }

    /**
     * @notice Attempt to mark the order as delivered
     * @dev It's called automatically by the IoT device automation
     * @param _orderAddress The address of the order
     */
    function deliverOrder(
        address _orderAddress
    ) public onlySender(_orderAddress) {
        callbackFlag = CallbackFlag.DELIVER_ORDER;
        lastCallerAddress = msg.sender;
        lastOrderAddress = _orderAddress;
        requestCurrentLocation();
    }

    /**
     * @notice Attempt to mark the order as confirmed
     * @dev Might be called by the sender after the order is delivered
     * @param _orderAddress The address of the order
     */
    function confirmOrderReceipt(
        address _orderAddress
    ) public onlyReceiver(_orderAddress) {
        callbackFlag = CallbackFlag.CONFIRM_ORDER_RECEIPT;
        lastCallerAddress = msg.sender;
        lastOrderAddress = _orderAddress;
        requestCurrentLocation();
    }

    /**
     * @notice Request the current location from the oracle
     * @dev The oracle will return the latitude and longitude in a single int256
     * @return requestId The id of the request
     */
    function requestCurrentLocation() public returns (bytes32 requestId) {
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfill.selector
        );

        // Set the URL to perform the GET request on
        req.add("get", "https://ship-track.fly.dev/locations/last");

        // Set the path to find the desired data in the API response:
        req.add("path", "location"); // Chainlink nodes 1.0.0 and later support this format

        req.addInt("times", 1);

        // Sends the request
        return sendChainlinkRequest(req, fee);
    }

    /**
     * @notice Callback function called by the oracle
     */
    function fulfill(
        bytes32 _requestId,
        int256 _rawData
    ) public recordChainlinkFulfillment(_requestId) {
        emit RequestFulfilled(_requestId, _rawData);
        (int32 curLat, int32 curLng) = convertInt256ToLatLng(_rawData);
        ordersState[lastOrder] = OrderState({
            curLat: curLat,
            curLng: curLng,
            timestamp: block.timestamp
        });

        if (callbackFlag == CallbackFlag.DELIVER_ORDER) {
            deliverOrderCallback();
        } else if (callbackFlag == CallbackFlag.CONFIRM_ORDER_RECEIPT) {
            confirmOrderReceiptCallback();
        }
    }

    /**
     * @notice Allow withdraw of Link tokens from the contract
     */
    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }

    /// @dev PRIVATE CALLBACKS
    function deliverOrderCallback() private {
        callbackFlag = CallbackFlag.NONE;
        if (checkLatLngThreshold(lastOrderAddress)) {
            emit OrderDelivered(lastOrderAddress);
        }
    }

    function confirmOrderReceiptCallback() private {
        callbackFlag = CallbackFlag.NONE;
        assertIsOrder(lastOrderAddress);
        Order order = orders[lastOrderAddress];
        order.confirmReceipt();
        emit OrderReceiptConfirmed(lastOrderAddress);
    }

    /// @dev PRIVATE CONSTANTS
    int32 private constant EARTH_CIRCUMFERENCE = 40075000; // in meters
    int32 private constant LATITUDE_RANGE = 180000000; // in microdegrees
    int32 private constant LONGITUDE_RANGE = 360000000; // in microdegrees

    /// @dev PRIVATE HELPERS
    function assertIsOrder(address _orderAddress) private view {
        require(
            address(orders[_orderAddress]) != address(0),
            "The order doesn't exist"
        );
    }

    function checkLatLngThreshold(
        address _orderAddress
    ) private returns (bool isDelivered) {
        assertIsOrder(_orderAddress);
        Order order = orders[_orderAddress];
        (int32 dstLat, int32 dstLng) = order.destinationLocation();
        int32 _curLat = ordersState[_orderAddress].curLat;
        int32 _curLng = ordersState[_orderAddress].curLng;

        // Verify latitude:
        int32 latDiff = _curLat - dstLat;
        if (latDiff < 0) {
            latDiff = -latDiff;
        }
        int32 latDistance = (latDiff * EARTH_CIRCUMFERENCE) / LATITUDE_RANGE;
        if (latDistance > deliveredDistanceThreshold) {
            return false;
        }

        // Verify longitude:
        int32 lngDiff = _curLng - dstLng;
        if (lngDiff < 0) {
            lngDiff = -lngDiff;
        }
        int32 lngDistance = (lngDiff * EARTH_CIRCUMFERENCE) / LONGITUDE_RANGE;
        if (lngDistance > deliveredDistanceThreshold) {
            return false;
        }

        order.deliver();
        return true;
    }

    function convertInt256ToLatLng(
        int256 _latLng
    ) private pure returns (int32, int32) {
        int32 lat = int32(_latLng >> 32);
        int32 lng = int32(_latLng) - LONGITUDE_RANGE;
        return (lat, lng);
    }
}
