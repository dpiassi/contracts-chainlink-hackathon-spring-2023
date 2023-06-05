// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
import "hardhat/console.sol";

/**
 * @title Order
 * @author Daniel Piassi
 * @notice A contract to store a delivery order
 */
contract Order {
    /// @notice A struct to store latitude and longitude
    struct LatLng {
        int32 latitude;
        int32 longitude;
    }

    /// @dev State variables
    address public sender;
    address public receiver;
    LatLng public sourceLocation;
    LatLng public destinationLocation;
    uint256 public expectedTimeOfArrival;
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
        uint256 _expectedTimeOfArrival
    ) {
        deliveryContract = msg.sender;
        sender = _sender;
        receiver = _receiver;
        sourceLocation = assertLatLng(_srcLat, _srcLng);
        destinationLocation = assertLatLng(_dstLat, _dstLng);
        expectedTimeOfArrival = _expectedTimeOfArrival;
    }

    /**
     * @notice The IoT device should mark the order as delivered.
     */
    function deliver() public onlyDeliveryContract {
        require(!delivered, "Order already delivered");
        // TODO implement late fee
        delivered = true;
    }

    /**
     * @notice The receiver may confirm the receipt of the order.
     */
    function confirmReceipt() public onlyDeliveryContract {
        require(!confirmed, "Order already confirmed");
        require(delivered, "Order not delivered yet");
        confirmed = true;
    }

    /// @dev PRIVATE CONSTANTS
    int32 private constant MAX_LATITUDE = 90000000;
    int32 private constant MIN_LATITUDE = -90000000;
    int32 private constant MAX_LONGITUDE = 180000000;
    int32 private constant MIN_LONGITUDE = -180000000;

    /// @dev PRIVATE FUNCTIONS
    function assertLatLng(
        int32 _latitude,
        int32 _longitude
    ) private pure returns (LatLng memory latLng) {
        assertLatitude(_latitude);
        assertLongitude(_longitude);
        return LatLng({latitude: _latitude, longitude: _longitude});
    }

    function assertLatitude(int32 latitude) private pure {
        require(
            latitude <= MAX_LATITUDE && latitude >= MIN_LATITUDE,
            "Latitude must be between -90 and 90 degrees"
        );
    }

    function assertLongitude(int32 longitude) private pure {
        require(
            longitude <= MAX_LONGITUDE && longitude >= MIN_LONGITUDE,
            "Longitude must be between -180 and 180 degrees"
        );
    }
}
