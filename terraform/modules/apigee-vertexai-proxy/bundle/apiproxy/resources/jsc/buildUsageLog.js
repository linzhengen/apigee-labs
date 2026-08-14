/*
 * Vertex AI のリクエスト/レスポンスから利用ログを組み立て、
 * Pub/Sub REST API (topics:publish) のリクエストボディを生成する。
 *
 * 出力: context 変数 usagelog.pubsub.payload (JSON 文字列)
 *   {"messages":[{"data":"<base64>","attributes":{...}}]}
 *
 * Apigee の JavaScript は Rhino (ES5) のため btoa / Buffer は使えない。
 * UTF-8 変換と Base64 エンコードは本ファイル内で実装する。
 */

var BASE64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

function toUtf8Bytes(str) {
  var bytes = [];
  for (var i = 0; i < str.length; i++) {
    var c = str.charCodeAt(i);
    if (c < 0x80) {
      bytes.push(c);
    } else if (c < 0x800) {
      bytes.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    } else if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
      var low = str.charCodeAt(i + 1);
      if (low >= 0xdc00 && low <= 0xdfff) {
        // サロゲートペア (絵文字など) を 1 コードポイントとして 4 バイトに変換
        var cp = 0x10000 + ((c - 0xd800) << 10) + (low - 0xdc00);
        bytes.push(
          0xf0 | (cp >> 18),
          0x80 | ((cp >> 12) & 0x3f),
          0x80 | ((cp >> 6) & 0x3f),
          0x80 | (cp & 0x3f)
        );
        i++;
      } else {
        // 対になっていないサロゲートは U+FFFD に置換
        bytes.push(0xef, 0xbf, 0xbd);
      }
    } else if (c >= 0xdc00 && c <= 0xdfff) {
      bytes.push(0xef, 0xbf, 0xbd);
    } else {
      bytes.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    }
  }
  return bytes;
}

function base64Encode(str) {
  var bytes = toUtf8Bytes(str);
  var out = "";
  for (var i = 0; i < bytes.length; i += 3) {
    var b0 = bytes[i];
    var hasB1 = i + 1 < bytes.length;
    var hasB2 = i + 2 < bytes.length;
    var b1 = hasB1 ? bytes[i + 1] : 0;
    var b2 = hasB2 ? bytes[i + 2] : 0;

    out += BASE64_CHARS.charAt(b0 >> 2);
    out += BASE64_CHARS.charAt(((b0 & 0x03) << 4) | (b1 >> 4));
    out += hasB1 ? BASE64_CHARS.charAt(((b1 & 0x0f) << 2) | (b2 >> 6)) : "=";
    out += hasB2 ? BASE64_CHARS.charAt(b2 & 0x3f) : "=";
  }
  return out;
}

function getVar(name) {
  var v = context.getVariable(name);
  return v === null || v === undefined ? null : String(v);
}

function toInt(value) {
  var n = parseInt(value, 10);
  return isNaN(n) ? 0 : n;
}

function truncate(text, maxChars) {
  if (text === null || text === undefined) {
    return null;
  }
  var s = String(text);
  return s.length > maxChars ? s.substring(0, maxChars) + "...[truncated]" : s;
}

function parseJson(text) {
  if (!text) {
    return null;
  }
  try {
    return JSON.parse(text);
  } catch (e) {
    return null;
  }
}

function isoTimestamp() {
  var d = new Date();
  if (typeof d.toISOString === "function") {
    return d.toISOString();
  }
  function pad(n, width) {
    var s = String(n);
    while (s.length < width) {
      s = "0" + s;
    }
    return s;
  }
  return (
    d.getUTCFullYear() +
    "-" + pad(d.getUTCMonth() + 1, 2) +
    "-" + pad(d.getUTCDate(), 2) +
    "T" + pad(d.getUTCHours(), 2) +
    ":" + pad(d.getUTCMinutes(), 2) +
    ":" + pad(d.getUTCSeconds(), 2) +
    "." + pad(d.getUTCMilliseconds(), 3) +
    "Z"
  );
}

/*
 * Vertex AI リクエストの contents[].parts[].text を連結してプロンプト文字列にする。
 * generateContent / streamGenerateContent いずれも同じ構造。
 */
function extractPrompt(requestBody) {
  var contents = requestBody && requestBody.contents;
  if (!contents) {
    return null;
  }
  if (!(contents instanceof Array)) {
    contents = [contents];
  }
  var texts = [];
  for (var i = 0; i < contents.length; i++) {
    var parts = contents[i] && contents[i].parts;
    if (!parts) {
      continue;
    }
    for (var j = 0; j < parts.length; j++) {
      if (parts[j] && typeof parts[j].text === "string") {
        texts.push(parts[j].text);
      }
    }
  }
  return texts.length > 0 ? texts.join("\n") : null;
}

/*
 * Vertex AI レスポンスの candidates[].content.parts[].text を連結する。
 * ストリーミングレスポンス (配列形式) にも対応する。
 */
function extractGeneratedText(responseBody) {
  if (!responseBody) {
    return null;
  }
  var chunks = responseBody instanceof Array ? responseBody : [responseBody];
  var texts = [];
  for (var i = 0; i < chunks.length; i++) {
    var candidates = chunks[i] && chunks[i].candidates;
    if (!candidates) {
      continue;
    }
    for (var j = 0; j < candidates.length; j++) {
      var parts = candidates[j] && candidates[j].content && candidates[j].content.parts;
      if (!parts) {
        continue;
      }
      for (var k = 0; k < parts.length; k++) {
        if (parts[k] && typeof parts[k].text === "string") {
          texts.push(parts[k].text);
        }
      }
    }
  }
  return texts.length > 0 ? texts.join("") : null;
}

/*
 * usageMetadata は EV-ExtractTokenCounts / AM-CleanTokenCounts が抽出済みの
 * context 変数を優先し、取得できなかった場合のみレスポンス本文から読む。
 */
function extractUsage(responseBody) {
  var usage = {
    prompt_token_count: toInt(getVar("promptTokenCount")),
    candidates_token_count: toInt(getVar("candidatesTokenCount")),
    total_token_count: toInt(getVar("totalTokenCount"))
  };
  if (usage.total_token_count > 0) {
    return usage;
  }

  var chunks = responseBody instanceof Array ? responseBody : [responseBody];
  for (var i = chunks.length - 1; i >= 0; i--) {
    var meta = chunks[i] && chunks[i].usageMetadata;
    if (meta) {
      return {
        prompt_token_count: toInt(meta.promptTokenCount),
        candidates_token_count: toInt(meta.candidatesTokenCount),
        total_token_count: toInt(meta.totalTokenCount)
      };
    }
  }
  return usage;
}

function main() {
  var maxPayloadChars = toInt(properties.maxPayloadChars) || 8000;
  var includePayloads = String(properties.includePayloads) === "true";

  // modelAction は "gemini-2.5-flash:generateContent" 形式
  var modelAction = getVar("modelAction") || "";
  var separatorIndex = modelAction.indexOf(":");
  var model = separatorIndex > 0 ? modelAction.substring(0, separatorIndex) : modelAction;
  var action = separatorIndex > 0 ? modelAction.substring(separatorIndex + 1) : null;

  var requestBody = parseJson(getVar("request.content"));
  var responseBody = parseJson(getVar("response.content"));

  var startedAt = getVar("client.received.start.timestamp");
  var now = getVar("system.timestamp");
  var latencyMs = startedAt && now ? toInt(now) - toInt(startedAt) : null;

  var logData = {
    transaction_id: getVar("messageid"),
    timestamp: isoTimestamp(),
    user_id: getVar("jwt.DJ-DecodeIapJwt.claim.email"),
    model: model || null,
    action: action,
    region: getVar("resolvedRegion") || "global",
    api_proxy: getVar("apiproxy.name"),
    api_proxy_revision: getVar("apiproxy.revision"),
    environment: getVar("environment.name"),
    status_code: toInt(getVar("response.status.code")),
    latency_ms: latencyMs,
    usage_metadata: extractUsage(responseBody)
  };

  if (includePayloads) {
    var prompt = extractPrompt(requestBody);
    var generatedText = extractGeneratedText(responseBody);
    logData.request = {
      prompt: truncate(prompt !== null ? prompt : getVar("request.content"), maxPayloadChars)
    };
    logData.response = {
      generated_text: truncate(
        generatedText !== null ? generatedText : getVar("response.content"),
        maxPayloadChars
      )
    };
  }

  // Pub/Sub REST API は messages[].data を Base64 エンコードして渡す必要がある
  var pubsubRequestBody = {
    messages: [
      {
        data: base64Encode(JSON.stringify(logData)),
        attributes: {
          source: "apigee",
          api_proxy: logData.api_proxy || "unknown",
          model: logData.model || "unknown"
        }
      }
    ]
  };

  context.setVariable("usagelog.pubsub.payload", JSON.stringify(pubsubRequestBody));
}

main();
