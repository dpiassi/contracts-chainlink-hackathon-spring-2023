// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

contract LatLngConverter {
  int32 private constant LONGITUDE_RANGE = 360000000; // in microdegrees

  function convertLatLngToInt256(int32 _lat, int32 _lng) public pure returns (int256) {
    int256 lat = int256(_lat) << 32;
    int256 lng = int256(_lng + LONGITUDE_RANGE);
    return lat | lng;
  }

  function convertInt256ToLatLng(int256 _latLng) public pure returns (int32, int32) {
    int32 lat = int32(_latLng >> 32);
    int32 lng = int32(_latLng) - LONGITUDE_RANGE;
    return (lat, lng);
  }
}
