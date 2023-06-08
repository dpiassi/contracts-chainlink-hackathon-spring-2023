// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// Uncomment this line to use console.log
import "hardhat/console.sol";

// Import chainlink/contracts framework dependencies
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

// Import local dependencies
import "./Order.sol";

/**
 * @title Shipping
 * @author Daniel Piassi
 * @notice This contract deals with the shipping process of delivering any kind of package in the real world. It gathers location data from IoT devices and stores it in the blockchain.
 * @dev Implementation using Chainlink External API Calls
 */
contract Shipping is ChainlinkClient, ConfirmedOwner {
  using Chainlink for Chainlink.Request;

  /// @dev Struct to store the last callback info
  struct OrderState {
    int32 curLat;
    int32 curLng;
    uint256 timestamp;
  }

  /// @dev State variables
  mapping(address => Order) private orders;
  mapping(address => address[]) private ordersBySender;
  mapping(address => address[]) private ordersByReceiver;
  address[] public orderAddresses;
  uint256 public ordersCount;
  address public lastOrder;
  int32 public deliveredDistanceThreshold = 400; // in meters

  /// @dev Chainlink External API Calls
  address private immutable oracle;
  bytes32 private immutable jobId;
  uint256 private immutable fee;

  /// @dev Multiple params returned in a single oracle response
  mapping(address => OrderState) public ordersState;

  /// @dev Events
  event OrderCreated(address indexed orderAddress);
  event OrderDelivered(address indexed orderAddress);
  event OrderReceiptConfirmed(address indexed orderAddress);
  event RequestFulfilled(bytes32 indexed requestId, int256 rawData);

  /// @dev State variables to store the last callback info
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
     * @notice Executes once when a contract is created to initialize state variables
     *
     * @param _oracle - address of the specific Chainlink node that a contract makes an API call from
     * @param _jobId - specific job for :_oracle: to run; each job is unique and returns different types of data
     * @param _fee - node operator price per API call / data request
     * @param _link - LINK token address on the corresponding network
     *
     * Network: Sepolia
     * Oracle: 0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD
     * Job ID: ca98366cc7314957b8c012c72f05aeeb
     * Fee: 0.1 LINK
     */
    constructor(address _oracle, bytes32 _jobId, uint256 _fee, address _link) ConfirmedOwner(msg.sender) {
        if (_link == address(0)) {
            setPublicChainlinkToken();
        } else {
            setChainlinkToken(_link);
        }
        oracle = _oracle;
        jobId = _jobId;
        fee = _fee;
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
    Order order = new Order(msg.sender, _receiver, _srcLat, _srcLng, _dstLat, _dstLng, _expectedTimeOfArrival);
    lastOrder = address(order);
    emit OrderCreated(lastOrder);
    orders[lastOrder] = order;
    orderAddresses.push(lastOrder);
    ordersBySender[msg.sender].push(lastOrder);
    ordersByReceiver[_receiver].push(lastOrder);
    ordersCount++;
    return lastOrder;
  }

  function getSenderOrders(address _sender) public view returns (address[] memory) {
    return ordersBySender[_sender];
  }

  function getReceiverOrders(address _receiver) public view returns (address[] memory) {
    return ordersByReceiver[_receiver];
  }

  /**
   * @notice We may change the distance threshold to consider the order as delivered
   * @param _deliveredDistanceThreshold The distance threshold to consider the order as delivered
   */
  function setDeliveredDistanceThreshold(int32 _deliveredDistanceThreshold) public onlyOwner {
    deliveredDistanceThreshold = _deliveredDistanceThreshold;
  }

  /**
   * @notice Attempt to mark the order as delivered
   * @dev It's called automatically by the IoT device automation
   * @param _orderAddress The address of the order
   */
  function deliverOrder(address _orderAddress) public onlySender(_orderAddress) {
    lastCallerAddress = msg.sender;
    lastOrderAddress = _orderAddress;
    requestCurrentLocation();
  }

  /**
   * @notice Attempt to mark the order as confirmed
   * @dev Might be called by the sender after the order is delivered
   * @param _orderAddress The address of the order
   */
  function confirmOrderReceipt(address _orderAddress) public onlyReceiver(_orderAddress) {
    assertIsOrder(_orderAddress);
    Order order = orders[_orderAddress];
    order.confirmReceipt();
    emit OrderReceiptConfirmed(_orderAddress);
  }

  /**
   * @notice Request the current location from the oracle
   * @dev The oracle will return the latitude and longitude in a single int256
   * @return requestId The id of the request
   */
  function requestCurrentLocation() public returns (bytes32 requestId) {
    Chainlink.Request memory req = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);

    // Set the URL to perform the GET request on
    req.add("get", string(abi.encodePacked("https://ship-track.fly.dev/locations/last/", lastOrderAddress)));

    // Set the path to find the desired data in the API response:
    req.add("path", "location");

    // Adjust the API Response to an int256:
    req.addInt("times", 1); // Useful when the result is a floating point number

    // Sends the request
    return sendChainlinkRequest(req, fee);
  }

  /**
   * @notice Callback function called by the oracle
   */
  function fulfill(bytes32 _requestId, int256 _rawData) public recordChainlinkFulfillment(_requestId) {
    emit RequestFulfilled(_requestId, _rawData);
    (int32 curLat, int32 curLng) = convertInt256ToLatLng(_rawData);
    ordersState[lastOrder] = OrderState({curLat: curLat, curLng: curLng, timestamp: block.timestamp});

    if (checkLatLngThreshold(lastOrderAddress)) {
      emit OrderDelivered(lastOrderAddress);
    }
  }

  /**
   * @notice Allow withdraw of Link tokens from the contract
   */
  function withdrawLink() public onlyOwner {
    LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
    require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
  }

  /// @dev PRIVATE CONSTANTS
  int32 private constant EARTH_CIRCUMFERENCE = 40075000; // in meters
  int32 private constant LATITUDE_RANGE = 180000000; // in microdegrees
  int32 private constant LONGITUDE_RANGE = 360000000; // in microdegrees

  /// @dev PRIVATE FUNCTIONS
  function assertIsOrder(address _orderAddress) private view {
    require(address(orders[_orderAddress]) != address(0), "The order doesn't exist");
  }

  function checkLatLngThreshold(address _orderAddress) private returns (bool isDelivered) {
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

  function convertInt256ToLatLng(int256 _latLng) private pure returns (int32, int32) {
    int32 lat = int32(_latLng >> 32);
    int32 lng = int32(_latLng) - LONGITUDE_RANGE;
    return (lat, lng);
  }
}
