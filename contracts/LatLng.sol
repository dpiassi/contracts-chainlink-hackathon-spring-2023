// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
import "hardhat/console.sol";

/**
 * @title LatLng
 * @author Daniel Piassi
 * @notice A contract to store a latitude and longitude
 */
contract LatLng {
    /// @dev Constants: latitude and longitude limits
    int32 public constant MAX_LATITUDE = 90000000;
    int32 public constant MIN_LATITUDE = -90000000;
    int32 public constant MAX_LONGITUDE = 180000000;
    int32 public constant MIN_LONGITUDE = -180000000;

    /// @dev State variables
    int32 public latitude;
    int32 public longitude;
    uint256 public timestamp;

    /// @notice The address of the order contract associated with this location
    address public orderContract;

    /// @dev Modifiers
    modifier onlyOrderContract() {
        require(msg.sender == orderContract, "You aren't the order contract");
        _;
    }

    /**
     * @notice Create a new LatLng object
     * @param _latitude The latitude of the location
     * @param _longitude The longitude of the location
     */
    constructor(int32 _latitude, int32 _longitude) public {
        require(
            _latitude <= MAX_LATITUDE && _latitude >= MIN_LATITUDE,
            "Latitude must be between -90 and 90 degrees"
        );
        require(
            _longitude <= MAX_LONGITUDE && _longitude >= MIN_LONGITUDE,
            "Longitude must be between -180 and 180 degrees"
        );

        orderContract = msg.sender;
        latitude = _latitude;
        longitude = _longitude;
        timestamp = block.timestamp;
    }
}
