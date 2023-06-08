// Arguments can be provided when a request is initated on-chain and used in the request source code as shown below
const ordersData = args;

console.log(ordersData);

// make HTTP request
const getUrl = "https://ship-track.fly.dev/locations2/last"
console.log(`HTTP GET Request to ${getUrl}`)

// construct the HTTP Request object. See: https://github.com/smartcontractkit/functions-hardhat-starter-kit#javascript-code
// params used for URL query parameters
const getLastLocationsRequest = Functions.makeHttpRequest({
  url: getUrl,
})

// Execute the API request (Promise)
const getLastLocationsResponse = await getLastLocationsRequest
if (getLastLocationsResponse.error) {
  console.error(getLastLocationsResponse.error)
  throw Error("Request failed")
}

const data = getLastLocationsResponse["data"]
if (data.Response === "Error") {
  console.error(data.Message)
  throw Error(`Functional error. Read message: ${data.Message}`)
}

// const DELIVERED_DISTANCE_THRESHOLD = 1000; // in meters
// const EARTH_CIRCUMFERENCE = 40075000; // in meters
// const LATITUDE_RANGE = 180000000; // in microdegrees
const LONGITUDE_RANGE = 360000000; // in microdegrees

// function checkLatLngThreshold(curLat, curLng, dstLat, dstLng) {
//   let latDiff = Math.abs(curLat - location.lat);
//   let latDistance = (latDiff / LATITUDE_RANGE) * EARTH_CIRCUMFERENCE;
//   if (latDistance > DELIVERED_DISTANCE_THRESHOLD) return false;
//   let lngDiff = Math.abs(curLng - location.lng);
//   let lngDistance = (lngDiff / LONGITUDE_RANGE) * EARTH_CIRCUMFERENCE;
//   if (lngDistance > DELIVERED_DISTANCE_THRESHOLD) return false;
//   return true;
// }


for (let i = 0; i < data.length; i++) {
  const snapshot = data[i];
  // Combine latitude (int32), longitude (int32) and orderId (hex string) into a single int256:



  // if (checkLatLngThreshold(snapshot.latitude, snapshot.longitude)) {
  //   return Functions.encodeUint256(snapshot.timestamp);
  // }
}

const price = data["RAW"][fromSymbol][toSymbol]["PRICE"]
console.log(`${fromSymbol} price is: ${price.toFixed(2)} ${toSymbol}`)

// Solidity doesn't support decimals so multiply by 100 and round to the nearest integer
// Use Functions.encodeUint256 to encode an unsigned integer to a Buffer
return Functions.encodeUint256(Math.round(price * 100))
