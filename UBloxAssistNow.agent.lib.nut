// MIT License
//
// Copyright 2019 Electric Imp
//
// SPDX-License-Identifier: MIT
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
// EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
// OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

// https://www.u-blox.com/sites/default/files/products/documents/MultiGNSS-Assistance_UserGuide_%28UBX-13004360%29.pdf
// MGA access tokens - http://www.u-blox.com/services-form.html
class UBloxAssistNow {

    static VERSION = "1.0.0";

    _token   = null;
    _headers = null;

    constructor(token) {
        const UBLOX_ASSISTNOW_ONLINE_URL     = "https://online-%s.services.u-blox.com/GetOnlineData.ashx";
        const UBLOX_ASSISTNOW_OFFLINE_URL    = "https://offline-%s.services.u-blox.com/GetOfflineData.ashx";
        const UBLOX_ASSISTNOW_PRIMARY_SERVER = "live1";
        const UBLOX_ASSISTNOW_BACKUP_SERVER  = "live2";
        const UBLOX_ASSISTNOW_UBX_MGA_ANO_CLASS_ID = 0x1320;

        _token   = token;
        _headers = {};
    }

    function setHeaders(headers) {
        _headers = headers;
    }

    function online(reqParams, cb) {
        local url = format("%s?token=%s;%s",
                      UBLOX_ASSISTNOW_ONLINE_URL, _token, _formatOptions(reqParams));
        _sendRequest(url, UBLOX_ASSISTNOW_PRIMARY_SERVER, cb);
    }

    function offline(reqParams, cb) {
        local url = format("%s?token=%s;%s",
                      UBLOX_ASSISTNOW_OFFLINE_URL, _token, _formatOptions(reqParams));
        _sendRequest(url, UBLOX_ASSISTNOW_PRIMARY_SERVER, cb);
    }

    // Splits offline response into messages organized by date
    // Returns a table of MGA_ANO messages, keys are date strings, values are a string of all MGA_ANO messages for that date.
    function getOfflineMsgByDate(offlineRes, logUnknownMsgType = false) {
        if (offlineRes.statuscode != 200) return {};

        // Get result as a blob as we iterate through it
        local v = blob();
        v.writestring(offlineRes.body);
        v.seek(0);

        // Make blank offline assist table to send to device
        // Table consists of date entries with binary strings of concatenated messages for that day
        local assist = {};

        // Build day buckets with all UBX-MGA-ANO messages for a single day in each
        while(v.tell() < v.len()) {
            // Read header & extract length
            local msg = v.readstring(6);
            local bodylen = msg[4] | (msg[5] << 8);
            local classid = msg[2] << 8 | msg[3];

            // Read message body & checksum bytes
            local body = v.readstring(2 + bodylen);

            // Check it's UBX-MGA-ANO
            if (classid == UBLOX_ASSISTNOW_UBX_MGA_ANO_CLASS_ID) {
                // Make date string
                // This will be for file name is SFFS is used on device
                local d = format("%04d%02d%02d", 2000 + body[4], body[5], body[6]);

                // New date? If so create day bucket
                if (!(d in assist)) assist[d] <- "";

                // Append to bucket
                assist[d] += (msg + body);
            } else if (logUnknownMsgType) {
                server.log(format("Unknown classid %04x in offline assist data", classid));
            }
        }

        return assist;
    }

    function _sendRequest(url, svr, cb) {
        local req = http.get(format(url, svr), _headers);
        req.sendasync(_respFactory(svr));
    }

    function _respFactory(url, svr, cb) {
        // Return a process response function
        return function(resp) {
            local status = resp.statuscode;
            local err = null;

            if (status == 403) {
                err = "ERROR: Overload limit reached.";
            } else if (status < 200 || status >= 300) {
                if (svr == UBLOX_ASSISTNOW_PRIMARY_SERVER) {
                    // Retry request using backup server instead
                    // TODO: May want to lengthen request timeout
                    _sendRequest(url, UBLOX_ASSISTNOW_BACKUP_SERVER, cb);
                    return;
                }
                // Body should contain an error message string
                err = resp.body;
            }

            cb(err, resp);
        }.bindenv(this);
    }

    function _formatOptions(opts) {
        local encoded = "";
        foreach(k, v in opts) {
            encoded += (k + "=");
            switch (typeof v) {
                case "string":
                case "integer":
                case "float":
                    ev += (v + ";");
                    break;
                case "array":
                    local last = v.len() - 1;
                    foreach(idx, item in v) {
                        encoded += (idx == last) ? (item + ";") : (item + ",");
                    }
                default:
                    // Data could not be formatted
                    return null;
            }
        }
        return encoded;
    }
}