#!/usr/bin/env node

function extractStreamInfoUrlFromHtmlForIpCamLive(htmlContent) {
  // Helper function to extract variables from script tags
  function extractVariable(html, varName) {
    const regex = new RegExp(`var ${varName}\\s*=\\s*['"]([^'"]*)['"];`);
    const match = html.match(regex);
    return match ? match[1] : null;
  }

  // Extract relevant variables
  const groupaddress = extractVariable(htmlContent, "groupaddress");
  const token = extractVariable(htmlContent, "token");
  const alias = extractVariable(htmlContent, "alias");

  // Construct the Url
  const domain = new URL(groupaddress).hostname;
  const timestamp = Date.now(); // Current timestamp

  const params = new URLSearchParams({
    _: timestamp,
    token: token,
    alias: alias,
    targetdomain: domain,
    bufferingpercent: "0",
  });

  const url = `https://${domain}/player/getcamerastreamstate.php?${params.toString()}`;
  return url;
}

async function extractVideoUrlForIpCamLive(uniqueId) {
  const u = "https://g0.ipcamlive.com/player/player.php?alias=" + uniqueId;

  const response = await fetch(u);
  if (response.status === 200) {
    const html = await response.text();

    const streamInfoUrl = extractStreamInfoUrlFromHtmlForIpCamLive(html);

    const streamDescriptiorJson = await fetch(streamInfoUrl);
    if (streamDescriptiorJson.status === 200) {
      const jsonText = await streamDescriptiorJson.text();
      const jsonObject = JSON.parse(jsonText);

      const baseAddress = jsonObject.details.address;
      const streamId = jsonObject.details.streamid;
      const streamUrl = `${baseAddress}streams/${streamId}/stream.m3u8`;

      return streamUrl;
    }
  }
}

const getCsopakUrl = async function () {
  const uniqueId = "66799108828d0";
  return await extractVideoUrlForIpCamLive(uniqueId);
};

async function main() {
  try {
    const targetStream = await getCsopakUrl();
    console.log(`target stream -> ${targetStream}`);
  } catch (err) {
    console.error("Failed to get target stream:", err);
    process.exitCode = 1;
  }
}

// Run the main function
if (require.main === module) {
  main();
}

module.exports = { main };
