// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
import "hardhat/console.sol";

// Import local dependencies
import "./LatLng.sol";

/**
 * @title Order
 * @author Daniel Piassi
 * @notice A contract to store a delivery order
 */
contract Order {
    /// @dev State variables
    address public sender;
    address public receiver;
    LatLng public sourceLocation;
    LatLng public destinationLocation;
    uint32 public expectedTimeOfArrival;
    bool public delivered;
    bool public confirmed;

    /// @notice The address of the delivery contract associated with this order
    address public deliveryContract;

    /// @dev Modifiers
    modifier onlyDeliveryContract() {
        require(
            msg.sender == deliveryContract,
            "You aren't the delivery contract"
        );
        _;
    }

    /**
     * @notice Create a new Order object
     * @param _sender The address of the sender
     * @param _receiver The address of the receiver
     * @param _srcLat The latitude of the source location
     * @param _srcLng The longitude of the source location
     * @param _dstLat The latitude of the destination location
     * @param _dstLng The longitude of the destination location
     * @param _expectedTimeOfArrival The expected time of arrival
     */
    constructor(
        address _sender,
        address _receiver,
        int32 _srcLat,
        int32 _srcLng,
        int32 _dstLat,
        int32 _dstLng,
        uint32 _expectedTimeOfArrival
    ) public {
        deliveryContract = msg.sender;
        sender = _sender;
        receiver = _receiver;
        sourceLocation = new LatLng(_srcLat, _srcLng);
        destinationLocation = new LatLng(_dstLat, _dstLng);
        expectedTimeOfArrival = _expectedTimeOfArrival;
    }

    function deliver() public onlyDeliveryContract {
        require(!delivered, "Order already delivered");
        // TODO apply late fee
        delivered = true;
    }

    function confirmReceipt() public onlyDeliveryContract {
        require(!confirmed, "Order already confirmed");
        require(delivered, "Order not delivered yet");
        confirmed = true;
    }
}
