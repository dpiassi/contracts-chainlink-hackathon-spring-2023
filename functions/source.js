// Arguments can be provided when a request is initated on-chain and used in the request source code as shown below
const targetOrderContractHash = args[0];

console.log(`targetOrderContractHash: ${targetOrderContractHash}`)

// make HTTP request
const getUrl = "https://ship-track.fly.dev/location/lastSerial"
console.log(`HTTP GET Request to ${getUrl}`)

// construct the HTTP Request object. See: https://github.com/smartcontractkit/functions-hardhat-starter-kit#javascript-code
// params used for URL query parameters
const request = Functions.makeHttpRequest({
  url: getUrl,
})

// Execute the API request (Promise)
const response = await request
if (response.error) {
  console.error(response.error)
  throw Error("Request failed")
}

const data = response["data"]
if (data.Response === "Error") {
  console.error(data.Message)
  throw Error(`Functional error. Read message: ${data.Message}`)
}

const DELIVERED_DISTANCE_THRESHOLD = 1000; // in meters
const EARTH_CIRCUMFERENCE = 40075000; // in meters
const LATITUDE_RANGE = 180000000; // in microdegrees
const LONGITUDE_RANGE = 360000000; // in microdegrees

function checkLatLngThreshold(curLat, curLng, dstLat, dstLng) {
  let latDiff = Math.abs(curLat - dstLat);
  let latDistance = BigInt(latDiff / LATITUDE_RANGE) * EARTH_CIRCUMFERENCE;
  if (latDistance > DELIVERED_DISTANCE_THRESHOLD) return false;
  let lngDiff = Math.abs(curLng - dstLng);
  let lngDistance = BigInt(lngDiff / LONGITUDE_RANGE) * EARTH_CIRCUMFERENCE;
  if (lngDistance > DELIVERED_DISTANCE_THRESHOLD) return false;
  return true;
}

console.log(`data: ${JSON.stringify(data)}`);
if (!data.hasOwnProperty(targetOrderContractHash)) {
  throw Error(`Order hash ${targetOrderContractHash} not found in data`);
}

const serializedLocation = BigInt(data[targetOrderContractHash]);
console.log(`serializedLocation: ${serializedLocation}`)

// Use Functions.encodeInt256 to encode a signed integer to a Buffer  
return Functions.encodeInt256(serializedLocation);
