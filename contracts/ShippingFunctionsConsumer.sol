// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// Uncomment this line to use console.log
import "hardhat/console.sol";

// Import Chainlink Functions framework dependencies
import {Functions, FunctionsClient} from "./dev/functions/FunctionsClient.sol";
// import "@chainlink/contracts/src/v0.8/dev/functions/FunctionsClient.sol"; // Once published

// Import chainlink/contracts framework dependencies
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

// Import openzeppelin/contracts utilities
import "@openzeppelin/contracts/utils/Strings.sol";

// Import local dependencies
import "./Order.sol";

/**
 * @title ShippingFunctionsConsumer
 * @author Daniel Piassi
 * @notice This contract deals with the shipping process of delivering any kind of package in the real world. It gathers location data from IoT devices and stores it in the blockchain.
 * @dev Implementation using Chainlink Functions framework
 */
contract ShippingFunctionsConsumer is FunctionsClient, ConfirmedOwner {
  using Functions for Functions.Request;

  /// @dev State variables for Chainlink Functions framework
  bytes32 public latestRequestId;
  bytes public latestResponse;
  bytes public latestError;

  /// @dev Event for Chainlink Functions framework
  event OCRResponse(bytes32 indexed requestId, bytes result, bytes err);

  /// @dev Struct to store the last callback info
  struct OrderState {
    int32 curLat;
    int32 curLng;
    uint256 timestamp;
  }

  /// @dev State variables
  mapping(address => Order) public orders;
  mapping(address => address[]) private ordersBySender;
  mapping(address => address[]) private ordersByReceiver;
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
   * @param oracle - The FunctionsOracle contract
   */
  constructor(address oracle) FunctionsClient(oracle) ConfirmedOwner(msg.sender) {}

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
  //   function deliverOrder(address _orderAddress) public onlySender(_orderAddress) {
  //     lastCallerAddress = msg.sender;
  //     lastOrderAddress = _orderAddress;
  //     requestCurrentLocation();
  //   }

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
   * @notice Send a simple request
   *
   * @param source JavaScript source code
   * @param secrets Encrypted secrets payload
   * @param args List of arguments accessible from within the source code
   * @param subscriptionId Funtions billing subscription ID
   * @param gasLimit Maximum amount of gas used to call the client contract's `handleOracleFulfillment` function
   * @return Functions request ID
   */
  function executeRequest(
    string calldata source,
    bytes calldata secrets,
    string[] calldata args,
    uint64 subscriptionId,
    uint32 gasLimit
  ) public onlyOwner returns (bytes32) {
    Functions.Request memory req;
    req.initializeRequest(Functions.Location.Inline, Functions.CodeLanguage.JavaScript, source);
    if (secrets.length > 0) req.addRemoteSecrets(secrets);
    // if (args.length > 0) req.addArgs(args);

    // string[] memory requestArgs;
    // uint256 requestArgsCount = 0;

    // Iterate over all orders:
    // for (uint256 i = 0; i < ordersCount; i++) {
    //   address orderAddress = orderAddresses[i];
    //   Order order = orders[orderAddress];
    //   if (order.delivered()) continue;
    //   requestArgs[requestArgsCount] = Strings.toHexString(uint160(orderAddress), 20);
    //   requestArgsCount++;
    // }

    require(lastOrder != address(0), "No orders created yet");

    string[] memory requestArgs;
    requestArgs = new string[](1 + args.length);
    for (uint256 i = 0; i < args.length; i++) {
      requestArgs[i] = args[i];
    }
    requestArgs[args.length] = Strings.toHexString(uint160(lastOrder), 20);
    req.addArgs(requestArgs);

    bytes32 assignedReqID = sendRequest(req, subscriptionId, gasLimit);
    latestRequestId = assignedReqID;
    return assignedReqID;
  }

  /**
   * @notice Callback that is invoked once the DON has resolved the request or hit an error
   *
   * @param requestId The request ID, returned by sendRequest()
   * @param response Aggregated response from the user code
   * @param err Aggregated error from the user code or from the execution pipeline
   * Either response or error parameter will be set, but never both
   */
  function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
    latestResponse = response;
    latestError = err;
    emit OCRResponse(requestId, response, err);

    // Check if error is empty:
    if (err.length == 0) {
      console.log("Response: ", string(response));
      console.log("Response length: ", response.length);
      console.log("Response to string: ", string(response));
      console.logInt(abi.decode(response, (int256)));

      // Convert response to int256:
      int256 _latLng = abi.decode(response, (int256));
      (int32 _curLat, int32 _curLng) = convertInt256ToLatLng(_latLng);
      console.logInt(_curLat);
      console.logInt(_curLng);
      ordersState[lastOrder].curLat = _curLat;
      ordersState[lastOrder].curLng = _curLng;
      ordersState[lastOrder].timestamp = block.timestamp;
      tryDeliverOrder(lastOrder);
    } else {
      console.log("Error: ", string(err));
    }
  }

  /**
   * @notice Allows the Functions oracle address to be updated
   *
   * @param oracle New oracle address
   */
  function updateOracleAddress(address oracle) public onlyOwner {
    setOracle(oracle);
  }

  function addSimulatedRequestId(address oracleAddress, bytes32 requestId) public onlyOwner {
    addExternalRequest(oracleAddress, requestId);
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
    int latDiff = _curLat - dstLat;
    if (latDiff < 0) latDiff = -latDiff;
    int latDistance = int(latDiff * EARTH_CIRCUMFERENCE) / LATITUDE_RANGE;
    if (latDistance > deliveredDistanceThreshold) return false;

    // Verify longitude:
    int lngDiff = _curLng - dstLng;
    if (lngDiff < 0) lngDiff = -lngDiff;
    int lngDistance = int(lngDiff * EARTH_CIRCUMFERENCE) / LONGITUDE_RANGE;
    if (lngDistance > deliveredDistanceThreshold) return false;

    order.deliver();
    return true;
  }

  function convertInt256ToLatLng(int256 _latLng) private pure returns (int32, int32) {
    int32 lat = int32(_latLng >> 32);
    int32 lng = int32(_latLng) - LONGITUDE_RANGE;
    return (lat, lng);
  }
}
