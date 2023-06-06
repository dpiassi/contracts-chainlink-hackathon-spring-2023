// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// Uncomment this line to use console.log
import "hardhat/console.sol";

// Import Chainlink Functions framework dependencies
import {Functions, FunctionsClient} from "./dev/functions/FunctionsClient.sol";
// import "@chainlink/contracts/src/v0.8/dev/functions/FunctionsClient.sol"; // Once published
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

// Import chainlink/contracts framework dependencies
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

// Import local dependencies
import "./Order.sol";

/**
 * @title Delivery
 * @author Daniel Piassi
 * @notice A contract to store a delivery
 */
contract DeliveryAutomatedFunctionsConsumer is
    FunctionsClient,
    ConfirmedOwner,
    AutomationCompatibleInterface
{
    using Functions for Functions.Request;

    /// @dev State variables for Chainlink Functions framework
    bytes public requestCBOR;
    bytes32 public latestRequestId;
    bytes public latestResponse;
    bytes public latestError;
    uint64 public subscriptionId;
    uint32 public fulfillGasLimit;
    uint256 public updateInterval;
    uint256 public lastUpkeepTimeStamp;
    uint256 public upkeepCounter;
    uint256 public responseCounter;

    /// @dev Event for Chainlink Functions framework
    event OCRResponse(bytes32 indexed requestId, bytes result, bytes err);

    /// @dev Enum to store the last callback info
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

    /// @dev Multiple params returned in a single oracle response
    mapping(address => OrderState) public ordersState;

    /// @dev Events
    event OrderCreated(address indexed orderAddress);
    event OrderDelivered(address indexed orderAddress);
    event OrderReceiptConfirmed(address indexed orderAddress);

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
     * @notice Executes once when a contract is created to initialize state variables
     *
     * @param oracle The FunctionsOracle contract
     * @param _subscriptionId The Functions billing subscription ID used to pay for Functions requests
     * @param _fulfillGasLimit Maximum amount of gas used to call the client contract's `handleOracleFulfillment` function
     * @param _updateInterval Time interval at which Chainlink Automation should call performUpkeep
     */
    constructor(
        address oracle,
        uint64 _subscriptionId,
        uint32 _fulfillGasLimit,
        uint256 _updateInterval
    ) FunctionsClient(oracle) ConfirmedOwner(msg.sender) {
        updateInterval = _updateInterval;
        subscriptionId = _subscriptionId;
        fulfillGasLimit = _fulfillGasLimit;
        lastUpkeepTimeStamp = block.timestamp;
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
    // function deliverOrder(
    //     address _orderAddress
    // ) public onlySender(_orderAddress) {
    //     executeRequest();
    // }

    /**
     * @notice Attempt to mark the order as confirmed
     * @dev Might be called by the sender after the order is delivered
     * @param _orderAddress The address of the order
     */
    function confirmOrderReceipt(
        address _orderAddress
    ) public onlyReceiver(_orderAddress) {
        assertIsOrder(_orderAddress);
        Order order = orders[_orderAddress];
        order.confirmReceipt();
        emit OrderReceiptConfirmed(_orderAddress);
    }

    /**
     * @notice Generates a new Functions.Request. This pure function allows the request CBOR to be generated off-chain, saving gas.
     *
     * @param source JavaScript source code
     * @param secrets Encrypted secrets payload
     * @param args List of arguments accessible from within the source code
     */
    function generateRequest(
        string calldata source,
        bytes calldata secrets,
        string[] calldata args
    ) public pure returns (bytes memory) {
        Functions.Request memory req;
        req.initializeRequest(
            Functions.Location.Inline,
            Functions.CodeLanguage.JavaScript,
            source
        );
        if (secrets.length > 0) {
            req.addRemoteSecrets(secrets);
        }
        if (args.length > 0) req.addArgs(args);

        return req.encodeCBOR();
    }

    /**
   * @notice Sets the bytes representing the CBOR-encoded Functions.Request that is sent when performUpkeep is called

   * @param _subscriptionId The Functions billing subscription ID used to pay for Functions requests
   * @param _fulfillGasLimit Maximum amount of gas used to call the client contract's `handleOracleFulfillment` function
   * @param _updateInterval Time interval at which Chainlink Automation should call performUpkeep
   * @param newRequestCBOR Bytes representing the CBOR-encoded Functions.Request
   */
    function setRequest(
        uint64 _subscriptionId,
        uint32 _fulfillGasLimit,
        uint256 _updateInterval,
        bytes calldata newRequestCBOR
    ) external onlyOwner {
        updateInterval = _updateInterval;
        subscriptionId = _subscriptionId;
        fulfillGasLimit = _fulfillGasLimit;
        requestCBOR = newRequestCBOR;
    }

    /**
     * @notice Used by Automation to check if performUpkeep should be called.
     *
     * The function's argument is unused in this example, but there is an option to have Automation pass custom data
     * that can be used by the checkUpkeep function.
     *
     * Returns a tuple where the first element is a boolean which determines if upkeep is needed and the
     * second element contains custom bytes data which is passed to performUpkeep when it is called by Automation.
     */
    function checkUpkeep(
        bytes memory
    ) public view override returns (bool upkeepNeeded, bytes memory) {
        upkeepNeeded = (block.timestamp - lastUpkeepTimeStamp) > updateInterval;
    }

    /**
     * @notice Called by Automation to trigger a Functions request
     *
     * The function's argument is unused in this example, but there is an option to have Automation pass custom data
     * returned by checkUpkeep (See Chainlink Automation documentation)
     */
    function performUpkeep(bytes calldata) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        require(upkeepNeeded, "Time interval not met");
        lastUpkeepTimeStamp = block.timestamp;
        upkeepCounter = upkeepCounter + 1;

        bytes32 requestId = s_oracle.sendRequest(
            subscriptionId,
            requestCBOR,
            fulfillGasLimit
        );

        s_pendingRequests[requestId] = s_oracle.getRegistry();
        emit RequestSent(requestId);
        latestRequestId = requestId;
    }

    /**
     * @notice Callback that is invoked once the DON has resolved the request or hit an error
     *
     * @param requestId The request ID, returned by sendRequest()
     * @param response Aggregated response from the user code
     * @param err Aggregated error from the user code or from the execution pipeline
     * Either response or error parameter will be set, but never both
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        latestResponse = response;
        latestError = err;
        responseCounter = responseCounter + 1;
        emit OCRResponse(requestId, response, err);
    }

    /**
     * @notice Allows the Functions oracle address to be updated
     *
     * @param oracle New oracle address
     */
    function updateOracleAddress(address oracle) public onlyOwner {
        setOracle(oracle);
    }

    /// @dev PRIVATE CALLBACKS
    function tryDeliverOrder(address _orderAddress) private {
        if (checkLatLngThreshold(_orderAddress)) {
            emit OrderDelivered(_orderAddress);
        }
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
