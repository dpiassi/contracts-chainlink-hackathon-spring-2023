// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
import "hardhat/console.sol";

// Import chainlink/contracts framework dependencies
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

// Import local dependencies
import "./LatLng.sol";
import "./Order.sol";

/**
 * @title Delivery
 * @author Daniel Piassi
 * @notice A contract to store a delivery
 */
contract Delivery is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    /// @dev State variables
    mapping(address => Order) public orders;
    uint256 public ordersCount;

    /// @dev Chainlink External API Calls
    bytes32 private jobId;
    uint256 private fee;

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
     *
     * Sepolia Testnet details:
     * Oracle: 0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD (Chainlink DevRel)
     * jobId: ca98366cc7314957b8c012c72f05aeeb
     */
    constructor() public ConfirmedOwner(msg.sender) {
        setChainlinkToken(0x779877A7B0D9E8603169DdbD7836e478b4624789);
        setChainlinkOracle(0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD);
        jobId = "ca98366cc7314957b8c012c72f05aeeb"; // uint256
        fee = (1 * LINK_DIVISIBILITY) / 10; // 0,1 * 10**18 (Varies by network and job)
    }

    /**
     * @notice Create a new Order object
     * @param _receiver The address of the receiver
     * @param _srcLat The latitude of the source location
     * @param _srcLng The longitude of the source location
     * @param _dstLat The latitude of the destination location
     * @param _dstLng The longitude of the destination location
     * @param _expectedTimeOfArrival The expected time of arrival
     */
    function createOrder(
        address _receiver,
        int32 _srcLat,
        int32 _srcLng,
        int32 _dstLat,
        int32 _dstLng,
        uint32 _expectedTimeOfArrival
    ) public {
        Order order = new Order(
            msg.sender,
            _receiver,
            _srcLat,
            _srcLng,
            _dstLat,
            _dstLng,
            _expectedTimeOfArrival
        );
        orders[address(order)] = order;
        ordersCount++;
    }

    function confirmOrderReceipt(
        address _orderAddress
    ) public onlyReceiver(_orderAddress) {
        Order order = orders[_orderAddress];
        order.confirmReceipt();
    }

    function deliverOrder(
        address _orderAddress
    ) public onlySender(_orderAddress) {
        Order order = orders[_orderAddress];
        order.deliver();
    }

    function assertIsOrder(address _orderAddress) private view {
        require(
            address(orders[_orderAddress]) != address(0),
            "The order doesn't exist"
        );
    }

    // TODO call chainlink oracle to get the current location of the order etc.
}
