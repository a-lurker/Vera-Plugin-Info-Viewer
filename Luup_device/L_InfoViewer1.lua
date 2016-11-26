-- Info Viewer
-- Written by a-lurker (c) 28 Jan 2013.
-- Based on the ideas found in a plugin developed by Ap15e.
-- ZShark by gengen
-- Updated by gengen 30 October 2016.
-- Updated by a-lurker 26 November 2016.


--[[
    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    version 3 (GPLv3) as published by the Free Software Foundation;

    In addition to the GPLv3 License, this software is only for private
    or home usage. Commercial utilisation is not authorized.

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
]]

local PLUGIN_NAME     = 'InfoViewer'
local PLUGIN_SID      = 'urn:a-lurker-com:serviceId:'..PLUGIN_NAME..'1'
local PLUGIN_VERSION  = '0.68'
local THIS_LUL_DEVICE = nil

local PLUGIN_URL_ID = 'al_info'
local URL_ID = './data_request?id=lr_'..PLUGIN_URL_ID

local bit = require "bit"

-- initial number of lines to show
local INITIAL_LINES = 1000

-- an Lua pattern that suits the Lua find function
local luaPattern    = ''
local latestPattern = ''

local HD_SID  = 'urn:micasaverde-com:serviceId:HaDevice1'
local ZW_SID  = 'urn:micasaverde-com:serviceId:ZWaveNetwork1'
local ZWD_SID = 'urn:micasaverde-com:serviceId:ZWaveDevice1'

-- ordered array of Z-Wave devices
local zwDevices = {}

-- maps node number to its ordered location in the zw devices table
local reverseLookup = {}

-- longest description string - used for table formatting
local maxDescLength = 0

-- HTML escapes
local htmlEscapes = {
  nbsp=" ",
  quot='"',
  amp='&',
  lt="<",
  gt=">",
}

local APPS = {
    localapp  = {
        shell = '',
        title = 'Vera log file',
        host  = 'Vera',
        file  = '/var/log/cmh/LuaUPnP.log'
    },
}

local zwBasicTypes = {
	["1"]="Controller",
	["2"]="Static controller",
	["3"]="Slave",
	["4"]="Routing slave",
}

local zwClasses     = nil
local zwDeviceTypes = nil

-- you can turn on Verbose Logging - refer to: Vera-->U15-->SETUP-->Logs-->Verbose_Logging
-- http://vera_ip_address/cgi-bin/cmh/log_level.sh?command=enable&log=VERBOSE
-- http://vera_ip_address/cgi-bin/cmh/log_level.sh?command=disable&log=VERBOSE
local DEBUG_MODE = false
local debug_file = nil

local function debug(textParm, logLevel)
    if DEBUG_MODE then
        local text = ''
        local theType = type(textParm)
        if (theType == 'string') then
            text = textParm
        else
            text = 'type = '..theType..', value = '..tostring(textParm)
        end
        luup.log(PLUGIN_NAME..' debug: '..text,50)

    elseif (logLevel) then
        local text = ''
        if (type(textParm) == 'string') then text = textParm end
        luup.log(PLUGIN_NAME..' debug: '..text, logLevel)
    end
end

-- return the value of a bit in a byte
-- byte is an 8 bit binary string
-- bitPos is 0 to 7
local function getBit(byte, bitPos)
    return (byte:sub(8-bitPos,8-bitPos) == '1')
end

-- escape text chars to suit json
-- http://www.ietf.org/rfc/rfc4627.txt
local function escJSONentities(s)
    s = s:gsub('\\', '\\u005c')
    s = s:gsub('\n', '\\u000a')
    s = s:gsub('"',  '\\u0022')
    s = s:gsub("'",  '\\u0027')
    s = s:gsub('/',  '\\u002f')
    s = s:gsub('\t', '\\u0009')
    return s
end

-- escape to suit html
local function escXMLentities(s)
    s = s:gsub('&', '&amp;')
    s = s:gsub('<', '&lt;')
    s = s:gsub('>', '&gt;')
    s = s:gsub('"', '&quot;')
    s = s:gsub("'", '&#39;')
    return s
end

-- justify a string
-- s: string to justify
-- width: width to justify to (+ve means right-justify; negative means left-justify)
-- [padder]: string to pad with (" " if omitted)
-- returns s: justified string
function pad(s, width, padder)
    padder = string.rep(padder or " ", math.abs(width))
    if width < 0 then
        return string.sub(padder..s, width) end
    return string.sub(s..padder, 1, width)
end

-- Convert a decimal string to a string of base of binary power x padded with leading zeros to match width
function dec2StrInBase(dec, base, width)
    local chrSet = '0123456789ABCDEF'
    local intVar = 0
    local result = ''

    dec = tonumber(dec)
    while dec > 0 do
        intVar = math.mod  (dec,base) + 1
        dec    = math.floor(dec/base)
        result = string.sub(chrSet,intVar,intVar)..result
    end

    return pad (result, -width, '0')
end

----begin dkjson decode
------------------------------------------------------------------------
--[[ David Kolf's JSON module for Lua 5.1/5.2
    Version 1.2.1

    Exported functions and values:
    json.null
      You can use this value for setting explicit 'null' values.

    json.decode (string [, position [, null] ])
     Decode 'string' starting at 'position' or at 1 if 'position' was
     omitted.

     'null' is an optional value to be returned for null values. The
     default is 'nil', but you could set it to json.null or any other
     value.

     The return values are the object or nil, the position of the next
     character that doesn't belong to the object, and in case of errors
     an error message.

     You can contact the author by sending an e-mail to 'david' at the
     domain 'dkolf.de'.

    Copyright (C) 2010-2013 David Heiko Kolf

    Permission is hereby granted, free of charge, to any person obtaining
    a copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be
    included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
    NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
    BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
    ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
    CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
]]

JSON =

{
loc = function(str, where)
  local line, pos, linepos = 1, 1, 0
  while true do
    pos = string.find (str, "\n", pos, true)
    if pos and pos < where then
      line = line + 1
      linepos = pos
      pos = pos + 1
    else
      break
    end
  end
  return "line " .. line .. ", column " .. (where - linepos)
end,

unterminated = function(str, what, where)
  return nil, string.len (str) + 1, "unterminated " .. what .. " at " .. JSON.loc (str, where)
end,

scanwhite = function(str, pos)
  while true do
    pos = string.find (str, "%S", pos)
    if not pos then return nil end
    if string.sub (str, pos, pos + 2) == "\239\187\191" then
      -- UTF-8 Byte Order Mark
      pos = pos + 3
    else
      return pos
    end
  end
end,

escapechars = {
  ["b"] = "\b", ["f"] = "\f",
  ["n"] = "\n", ["r"] = "\r", ["t"] = "\t"
},

unichar = function(value)
  if value < 0 then
    return nil
  elseif value <= 0x007f then
    return string.char (value)
  elseif value <= 0x07ff then
    return string.char (0xc0 + floor(value/0x40),
                    0x80 + (floor(value) % 0x40))
  elseif value <= 0xffff then
    return string.char (0xe0 + floor(value/0x1000),
                    0x80 + (floor(value/0x40) % 0x40),
                    0x80 + (floor(value) % 0x40))
  elseif value <= 0x10ffff then
    return string.char (0xf0 + floor(value/0x40000),
                    0x80 + (floor(value/0x1000) % 0x40),
                    0x80 + (floor(value/0x40) % 0x40),
                    0x80 + (floor(value) % 0x40))
  else
    return nil
  end
end,

scanstring = function(str, pos)
  local lastpos = pos + 1
  local buffer, n = {}, 0
  while true do
    local nextpos = string.find (str, "[\"\\]", lastpos)
    if not nextpos then
      return JSON.unterminated (str, "string", pos)
    end
    if nextpos > lastpos then
      n = n + 1
      buffer[n] = string.sub (str, lastpos, nextpos - 1)
    end
    if string.sub (str, nextpos, nextpos) == "\"" then
      lastpos = nextpos + 1
      break
    else
      local escchar = string.sub (str, nextpos + 1, nextpos + 1)
      local value
      if escchar == "u" then
        value = tonumber (string.sub (str, nextpos + 2, nextpos + 5), 16)
        if value then
          local value2
          if 0xD800 <= value and value <= 0xDBff then
            -- we have the high surrogate of UTF-16. Check if there is a
            -- low surrogate escaped nearby to combine them.
            if string.sub (str, nextpos + 6, nextpos + 7) == "\\u" then
              value2 = tonumber (string.sub (str, nextpos + 8, nextpos + 11), 16)
              if value2 and 0xDC00 <= value2 and value2 <= 0xDFFF then
                value = (value - 0xD800)  * 0x400 + (value2 - 0xDC00) + 0x10000
              else
                value2 = nil -- in case it was out of range for a low surogate
              end
            end
          end
          value = value and JSON.unichar (value)
          if value then
            if value2 then
              lastpos = nextpos + 12
            else
              lastpos = nextpos + 6
            end
          end
        end
      end
      if not value then
        value = JSON.escapechars[escchar] or escchar
        lastpos = nextpos + 2
      end
      n = n + 1
      buffer[n] = value
    end
  end
  if n == 1 then
    return buffer[1], lastpos
  elseif n > 1 then
    return table.concat (buffer), lastpos
  else
    return "", lastpos
  end
end,

scantable = function(what, closechar, str, startpos, nullval)
  local len = string.len (str)
  local tbl, n = {}, 0
  local pos = startpos + 1
  while true do
    pos = JSON.scanwhite (str, pos)
    if not pos then return JSON.unterminated (str, what, startpos) end
    local char = string.sub (str, pos, pos)
    if char == closechar then
      return tbl, pos + 1
    end
    local val1, err
    val1, pos, err = JSON.decode (str, pos, nullval)
    if err then return nil, pos, err end
    pos = JSON.scanwhite (str, pos)
    if not pos then return JSON.unterminated (str, what, startpos) end
    char = string.sub (str, pos, pos)
    if char == ":" then
      if val1 == nil then
        return nil, pos, "cannot use nil as table index (at " .. JSON.loc (str, pos) .. ")"
      end
      pos = JSON.scanwhite (str, pos + 1)
      if not pos then return JSON.unterminated (str, what, startpos) end
      local val2
      val2, pos, err = JSON.decode (str, pos, nullval)
      if err then return nil, pos, err end
      tbl[val1] = val2
      pos = JSON.scanwhite (str, pos)
      if not pos then return JSON.unterminated (str, what, startpos) end
      char = string.sub (str, pos, pos)
    else
      n = n + 1
      tbl[n] = val1
    end
    if char == "," then
      pos = pos + 1
    end
  end
end,

decode = function (str, pos, nullval)
  pos = pos or 1
  pos = JSON.scanwhite (str, pos)
  if not pos then
    return nil, string.len (str) + 1, "no valid JSON value (reached the end)"
  end
  local char = string.sub (str, pos, pos)
  if char == "{" then
    return JSON.scantable ("object", "}", str, pos, nullval)
  elseif char == "[" then
    return JSON.scantable ("array", "]", str, pos, nullval)
  elseif char == "\"" then
    return JSON.scanstring (str, pos)
  else
    local pstart, pend = string.find (str, "^%-?[%d%.]+[eE]?[%+%-]?%d*", pos)
    if pstart then
      local number = tonumber (string.sub (str, pstart, pend))
      if number then
        return number, pend + 1
      end
    end
    pstart, pend = string.find (str, "^%a%w*", pos)
    if pstart then
      local name = string.sub (str, pstart, pend)
      if name == "true" then
        return true, pend + 1
      elseif name == "false" then
        return false, pend + 1
      elseif name == "null" then
        return nullval, pend + 1
      end
    end
    return nil, pos, "no valid JSON value at " .. JSON.loc (str, pos)
  end
end
} -- JSON
----End dkjson decode


-- See if a particular file is in place. This can be
-- used to check for the presence of various plugins.
function isFilePresent(checkThisFile)

    -- WC word count command - get newline (\n) count
    -- '2>&1' pipes stderr into our file
    local cmd = 'wc -l '..checkThisFile..' 2>&1'
    debug(cmd)

    -- f is of type 'userdata' and will not be nil if the command fails - that's why we also pipe in the stderr stream
    local f = io.popen(cmd)

    local lineCountStr = f:read()

    f:close()

    lineCountStr = lineCountStr:lower()
    debug('lineCountStr1 = '..lineCountStr)

    -- was an error message piped into the file?
    local error = lineCountStr:find('no such file')

    -- a total hack but we know if the file was found or not
    if error then return false end
    return true
end

local function htmlCssStyle1()
return [[
<style type="text/css">

body {
    background-color: black;
	color: white;
    font-family: verdana, arial, sans-serif;
}

#topRibbon {
	position: fixed;
	top: 0px;
	left: 0px;
	height: 30px;
	width: 100%;
	z-index: 1;
	overflow: visible;
	background-color: #808000;
}

#scrollArea {
	position: absolute;
	top: 30px;
	left: 0px;
	right: 0px;
	bottom: 30px;
	overflow: visible;
}

#bottomRibbon {
	position: fixed;
	height: 30px;
	left: 0px;
	width: 100%;
	bottom: 0px;
	overflow: hidden;
	z-index: 1;
	background-color: #904050;
}

#bottomDummy {
	height: 30px;
	background-color: black;
	left: 0px;
	width: 100%;
}

.button {
   margin: 1px 5px;
   display: inline-block;
   border-top: 1px solid #96d1f8;
   background: #65a9d7;
   background: -webkit-gradient(linear, left top, left bottom, from(#3e779d), to(#65a9d7));
   background: -webkit-linear-gradient(top, #3e779d, #65a9d7);
   background: -moz-linear-gradient(top, #3e779d, #65a9d7);
   background: -ms-linear-gradient(top, #3e779d, #65a9d7);
   background: -o-linear-gradient(top, #3e779d, #65a9d7);
   padding: 5px 10px;
   -webkit-border-radius: 8px;
   -moz-border-radius: 8px;
   border-radius: 8px;
   -webkit-box-shadow: rgba(0,0,0,1) 0 1px 0;
   -moz-box-shadow: rgba(0,0,0,1) 0 1px 0;
   box-shadow: rgba(0,0,0,1) 0 1px 0;
   text-shadow: rgba(0,0,0,.4) 0 1px 0;
   color: white;
   font-size: 14px;
   font-family: Georgia, serif;
   text-decoration: none;
   vertical-align: middle;
}

.button:hover {
   border-top-color: #28597a;
   background: #28597a;
   color: #ccc;
}

.button:active {
   border-top-color: #1b435e;
   background: #1b435e;
}

#sddm {
   margin: 0;
   padding: 0;
   display: inline-block;
}

#sddm li {
   margin: 0;
   padding: 0;
   list-style: none;
   float: left;
   font: bold 11px arial
}

#sddm li a, #sddm li span {
   display: block;
   margin: 0 1px 0 0;
   padding: 4px 10px;
   width: 60px;
   background: #5970B2;
   color: #FFF;
   text-align: center;
   text-decoration: none
}

#sddm li *:hover {
   background: #49A3FF
}

#sddm div {
   position: absolute;
   visibility: hidden;
   margin: 0;
   padding: 0;
   background: #EAEBD8;
   border: 1px solid #5970B2
}

#sddm div a, #sddm div li {
   position: static;
   display: block;
   margin: 0;
   padding: 5px 10px;
   width: auto;
   white-space: nowrap;
   text-align: left;
   text-decoration: none;
   background: #EAEBD8;
   color: #2875DE;
   font: 11px arial
}

#sddm div a:hover {
   background: #49A3FF;
   color: #FFF
}

.gap {
	width: 100%;
	background-image: -webkit-gradient(linear, left top, left bottom, color-stop(0, #000000), color-stop(0.5, #303030), color-stop(1, #000000));
	background-image: -o-linear-gradient(bottom, #000000 0%, #303030 50%, #000000 100%);
	background-image: -moz-linear-gradient(bottom, #000000 0%, #303030 50%, #000000 100%);
	background-image: -webkit-linear-gradient(bottom, #000000 0%, #303030 50%, #000000 100%);
	background-image: -ms-linear-gradient(bottom, #000000 0%, #303030 50%, #000000 100%);
	background-image: linear-gradient(to bottom, #000000 0%, #303030 50%, #000000 100%);
}

.interp_send {
	width: 100%;
	background-image: -webkit-gradient(linear, left top, left bottom, color-stop(0, #000000), color-stop(0.12, #008080), color-stop(1, #000000));
	background-image: -o-linear-gradient(bottom, #000000 0%, #008080 12%, #000000 100%);
	background-image: -moz-linear-gradient(bottom, #000000 0%, #008080 12%, #000000 100%);
	background-image: -webkit-linear-gradient(bottom, #000000 0%, #008080 12%, #000000 100%);
	background-image: -ms-linear-gradient(bottom, #000000 0%, #008080 12%, #000000 100%);
	background-image: linear-gradient(to bottom, #000000 0%, #008080 12%, #000000 100%);
}

.interp_receive {
	width: 100%;
	background-image: -webkit-gradient(linear, left top, left bottom, color-stop(0, #000000), color-stop(0.12, #000080), color-stop(1, #000000));
	background-image: -o-linear-gradient(bottom, #000000 0%, #000080 12%, #000000 100%);
	background-image: -moz-linear-gradient(bottom, #000000 0%, #000080 12%, #000000 100%);
	background-image: -webkit-linear-gradient(bottom, #000000 0%, #000080 12%, #000000 100%);
	background-image: -ms-linear-gradient(bottom, #000000 0%, #000080 12%, #000000 100%);
	background-image: linear-gradient(to bottom, #000000 0%, #000080 12%, #000000 100%);
}

.zcs0 { color: #A0A0FF; }
.zcs1 { color: #FFA0A0; }
.zcs2 { color: #FFFFFF; }
.zcs3 { color: #A0FFA0; }
.zcs4 { color: #FFA0FF; }
.zcs5 { color: #A0A0A0; }
.zcs6 { color: #A0FFFF; }
.zcs7 { color: #FFFFA0; }

</style>
]]
end


local function htmlCssStyle2()
return [[
<style type="text/css">

 .scripted-link { color: blue; text-decoration: underline; cursor: pointer; }

</style>
]]
end

local function htmkJavaScriptSource()
return [===[

function getURLpart(suffix) {
	if (document.URL.match(/fwd.*\.mios\.com/i)) {
		return("/remote/]]..luup.version..[[-en/"+suffix);
	} else {
		return(suffix);
	}
}

function ajaxRequest(url, args, callBack) {
	var xmlhttp;
	var first = true;
	for (var prop in args) {
		url += (first ? "?" : "&") + prop + "=" + args[prop];
		first = false;
	}
	if (window.XMLHttpRequest) {// code for IE7+, Firefox, Chrome, Opera, Safari
	  xmlhttp=new XMLHttpRequest();
	} else {// code for IE6, IE5
	  xmlhttp=new ActiveXObject("Microsoft.XMLHTTP");
	}
	xmlhttp.onreadystatechange=function() {
	  if (xmlhttp.readyState==4) {
		callBack(xmlhttp);
	  }
	}
	xmlhttp.open("GET",url,true);
	xmlhttp.send();
}

]===]
end

function htmlFixLights()
return [[
<script type="text/javascript">
	if (document.URL.match(/fwd.*\.mios\.com/i)) {
		function fixURL(id) {
			var obj = document.getElementById(id);
			var newURL = obj.src.replace(/\/cmh/,"/remote/]]..luup.version..[[-en");
			obj.src = newURL;
		}
		fixURL("pause-img");
		fixURL("play-img");
	}
</script>]]
end

-- Find out which device is the Z-Wave controller. It's normally
-- '1' but we'll make sure by finding it programmatically. However,
-- we "assume" it always exists.
-- There may be more than 1 if there are secondary controllers
-- attached as UPnP devices. We prefer #1 if it exists.
function getZWInterfacelId()
    local DEVICE_CATEGORY_ZWAVE_INT = 19
    local zwInt = -1
	v = luup.devices[1];
	if v ~= nil and v.category_num == DEVICE_CATEGORY_ZWAVE_INT then
		return 1
	end
    for k, v in pairs(luup.devices) do
        if (v.category_num == DEVICE_CATEGORY_ZWAVE_INT) then
            zwInt = k
        end
    end
    return zwInt
end

-- Get the Z-Wave information needed by ZShark as a JSON object.
function getJSONZWaveNodeList()
    local zwInt = getZWInterfacelId()
	local json = "{\n"
    for k, v in pairs(luup.devices) do
        -- we're only interested in the Z-Wave devices
        if (v.device_num_parent == zwInt) then
			json = json .. "  " .. v.id .. ": {deviceId: " .. k .. ", name: '" .. escJSONentities(v.description) .. "'},\n"
        end
    end
	json = json .. "}\n\n"
    return json
end

function getJSONZWaveKeys()
	local f = io.open("etc/cmh/keys","r")
	if not f then
		debug("keys file not found", 50);
		return "{}\n"
	end
    local data = f:read("*a");
	f:close();
	if #data < 48 then
		debug("keys data too short: " .. #data, 50);
		return "{}\n"
    end
	local strings = {}
    --for i = 1, 3 do
    for i = 1, 1 do
		local string = ""
		for j = 1, 16 do
			local x = data:byte((i-1)*16+j);
			string = string .. string.format("%02X", bit.bxor(x, 0x96));
		end
		strings[i] = string;
    end
    --return '{"M":"'..strings[1]..'","A":"'..strings[2]..'","E":"'..strings[3]..'"}\n'
    return '{"M":"'..strings[1]..'"}\n'
end

function GetAesJs()
return [===[
/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -  */
/*  AES implementation in JavaScript (c) Chris Veness 2005-2012                                   */
/*   - see http://csrc.nist.gov/publications/PubsFIPS.html#197                                    */
/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -  */

var Aes = {};  // Aes namespace

/**
 * AES Cipher function: encrypt 'input' state with Rijndael algorithm
 *   applies Nr rounds (10/12/14) using key schedule w for 'add round key' stage
 *
 * @param {Number[]} input 16-byte (128-bit) input state array
 * @param {Number[][]} w   Key schedule as 2D byte-array (Nr+1 x Nb bytes)
 * @returns {Number[]}     Encrypted output state array
 */
Aes.cipher = function(input, w) {    // main Cipher function [§5.1]
  var Nb = 4;               // block size (in words): no of columns in state (fixed at 4 for AES)
  var Nr = w.length/Nb - 1; // no of rounds: 10/12/14 for 128/192/256-bit keys

  var state = [[],[],[],[]];  // initialise 4xNb byte-array 'state' with input [§3.4]
  for (var i=0; i<4*Nb; i++) state[i%4][Math.floor(i/4)] = input[i];

  state = Aes.addRoundKey(state, w, 0, Nb);

  for (var round=1; round<Nr; round++) {
    state = Aes.subBytes(state, Nb);
    state = Aes.shiftRows(state, Nb);
    state = Aes.mixColumns(state, Nb);
    state = Aes.addRoundKey(state, w, round, Nb);
  }

  state = Aes.subBytes(state, Nb);
  state = Aes.shiftRows(state, Nb);
  state = Aes.addRoundKey(state, w, Nr, Nb);

  var output = new Array(4*Nb);  // convert state to 1-d array before returning [§3.4]
  for (var i=0; i<4*Nb; i++) output[i] = state[i%4][Math.floor(i/4)];
  return output;
}

/**
 * Perform Key Expansion to generate a Key Schedule
 *
 * @param {Number[]} key Key as 16/24/32-byte array
 * @returns {Number[][]} Expanded key schedule as 2D byte-array (Nr+1 x Nb bytes)
 */
Aes.keyExpansion = function(key) {  // generate Key Schedule (byte-array Nr+1 x Nb) from Key [§5.2]
  var Nb = 4;            // block size (in words): no of columns in state (fixed at 4 for AES)
  var Nk = key.length/4  // key length (in words): 4/6/8 for 128/192/256-bit keys
  var Nr = Nk + 6;       // no of rounds: 10/12/14 for 128/192/256-bit keys

  var w = new Array(Nb*(Nr+1));
  var temp = new Array(4);

  for (var i=0; i<Nk; i++) {
    var r = [key[4*i], key[4*i+1], key[4*i+2], key[4*i+3]];
    w[i] = r;
  }

  for (var i=Nk; i<(Nb*(Nr+1)); i++) {
    w[i] = new Array(4);
    for (var t=0; t<4; t++) temp[t] = w[i-1][t];
    if (i % Nk == 0) {
      temp = Aes.subWord(Aes.rotWord(temp));
      for (var t=0; t<4; t++) temp[t] ^= Aes.rCon[i/Nk][t];
    } else if (Nk > 6 && i%Nk == 4) {
      temp = Aes.subWord(temp);
    }
    for (var t=0; t<4; t++) w[i][t] = w[i-Nk][t] ^ temp[t];
  }

  return w;
}

/*
 * ---- remaining routines are private, not called externally ----
 */

Aes.subBytes = function(s, Nb) {    // apply SBox to state S [§5.1.1]
  for (var r=0; r<4; r++) {
    for (var c=0; c<Nb; c++) s[r][c] = Aes.sBox[s[r][c]];
  }
  return s;
}

Aes.shiftRows = function(s, Nb) {    // shift row r of state S left by r bytes [§5.1.2]
  var t = new Array(4);
  for (var r=1; r<4; r++) {
    for (var c=0; c<4; c++) t[c] = s[r][(c+r)%Nb];  // shift into temp copy
    for (var c=0; c<4; c++) s[r][c] = t[c];         // and copy back
  }          // note that this will work for Nb=4,5,6, but not 7,8 (always 4 for AES):
  return s;  // see asmaes.sourceforge.net/rijndael/rijndaelImplementation.pdf
}

Aes.mixColumns = function(s, Nb) {   // combine bytes of each col of state S [§5.1.3]
  for (var c=0; c<4; c++) {
    var a = new Array(4);  // 'a' is a copy of the current column from 's'
    var b = new Array(4);  // 'b' is a•{02} in GF(2^8)
    for (var i=0; i<4; i++) {
      a[i] = s[i][c];
      b[i] = s[i][c]&0x80 ? s[i][c]<<1 ^ 0x011b : s[i][c]<<1;

    }
    // a[n] ^ b[n] is a•{03} in GF(2^8)
    s[0][c] = b[0] ^ a[1] ^ b[1] ^ a[2] ^ a[3]; // 2*a0 + 3*a1 + a2 + a3
    s[1][c] = a[0] ^ b[1] ^ a[2] ^ b[2] ^ a[3]; // a0 * 2*a1 + 3*a2 + a3
    s[2][c] = a[0] ^ a[1] ^ b[2] ^ a[3] ^ b[3]; // a0 + a1 + 2*a2 + 3*a3
    s[3][c] = a[0] ^ b[0] ^ a[1] ^ a[2] ^ b[3]; // 3*a0 + a1 + a2 + 2*a3
  }
  return s;
}

Aes.addRoundKey = function(state, w, rnd, Nb) {  // xor Round Key into state S [§5.1.4]
  for (var r=0; r<4; r++) {
    for (var c=0; c<Nb; c++) state[r][c] ^= w[rnd*4+c][r];
  }
  return state;
}

Aes.subWord = function(w) {    // apply SBox to 4-byte word w
  for (var i=0; i<4; i++) w[i] = Aes.sBox[w[i]];
  return w;
}

Aes.rotWord = function(w) {    // rotate 4-byte word w left by one byte
  var tmp = w[0];
  for (var i=0; i<3; i++) w[i] = w[i+1];
  w[3] = tmp;
  return w;
}

// sBox is pre-computed multiplicative inverse in GF(2^8) used in subBytes and keyExpansion [§5.1.1]
Aes.sBox =  [0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
             0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
             0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
             0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
             0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
             0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
             0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
             0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
             0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
             0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
             0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
             0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
             0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
             0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
             0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
             0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16];

// rCon is Round Constant used for the Key Expansion [1st col is 2^(r-1) in GF(2^8)] [§5.2]
Aes.rCon = [ [0x00, 0x00, 0x00, 0x00],
             [0x01, 0x00, 0x00, 0x00],
             [0x02, 0x00, 0x00, 0x00],
             [0x04, 0x00, 0x00, 0x00],
             [0x08, 0x00, 0x00, 0x00],
             [0x10, 0x00, 0x00, 0x00],
             [0x20, 0x00, 0x00, 0x00],
             [0x40, 0x00, 0x00, 0x00],
             [0x80, 0x00, 0x00, 0x00],
             [0x1b, 0x00, 0x00, 0x00],
             [0x36, 0x00, 0x00, 0x00] ];


/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -  */
/*  AES Counter-mode implementation in JavaScript (c) Chris Veness 2005-2012                      */
/*   - see http://csrc.nist.gov/publications/nistpubs/800-38a/sp800-38a.pdf                       */
/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -  */

Aes.Ctr = {};  // Aes.Ctr namespace: a subclass or extension of Aes

/**
 * Encrypt a text using AES encryption in Counter mode of operation
 *
 * Unicode multi-byte character safe
 *
 * @param {String} plaintext Source text to be encrypted
 * @param {String} password  The password to use to generate a key
 * @param {Number} nBits     Number of bits to be used in the key (128, 192, or 256)
 * @returns {string}         Encrypted text
 */
Aes.Ctr.encrypt = function(plaintext, password, nBits) {
  var blockSize = 16;  // block size fixed at 16 bytes / 128 bits (Nb=4) for AES
  if (!(nBits==128 || nBits==192 || nBits==256)) return '';  // standard allows 128/192/256 bit keys
  plaintext = Utf8.encode(plaintext);
  password = Utf8.encode(password);
  //var t = new Date();  // timer

  // use AES itself to encrypt password to get cipher key (using plain password as source for key
  // expansion) - gives us well encrypted key (though hashed key might be preferred for prod'n use)
  var nBytes = nBits/8;  // no bytes in key (16/24/32)
  var pwBytes = new Array(nBytes);
  for (var i=0; i<nBytes; i++) {  // use 1st 16/24/32 chars of password for key
    pwBytes[i] = isNaN(password.charCodeAt(i)) ? 0 : password.charCodeAt(i);
  }
  var key = Aes.cipher(pwBytes, Aes.keyExpansion(pwBytes));  // gives us 16-byte key
  key = key.concat(key.slice(0, nBytes-16));  // expand key to 16/24/32 bytes long

  // initialise 1st 8 bytes of counter block with nonce (NIST SP800-38A §B.2): [0-1] = millisec,
  // [2-3] = random, [4-7] = seconds, together giving full sub-millisec uniqueness up to Feb 2106
  var counterBlock = new Array(blockSize);

  var nonce = (new Date()).getTime();  // timestamp: milliseconds since 1-Jan-1970
  var nonceMs = nonce%1000;
  var nonceSec = Math.floor(nonce/1000);
  var nonceRnd = Math.floor(Math.random()*0xffff);

  for (var i=0; i<2; i++) counterBlock[i]   = (nonceMs  >>> i*8) & 0xff;
  for (var i=0; i<2; i++) counterBlock[i+2] = (nonceRnd >>> i*8) & 0xff;
  for (var i=0; i<4; i++) counterBlock[i+4] = (nonceSec >>> i*8) & 0xff;

  // and convert it to a string to go on the front of the ciphertext
  var ctrTxt = '';
  for (var i=0; i<8; i++) ctrTxt += String.fromCharCode(counterBlock[i]);

  // generate key schedule - an expansion of the key into distinct Key Rounds for each round
  var keySchedule = Aes.keyExpansion(key);

  var blockCount = Math.ceil(plaintext.length/blockSize);
  var ciphertxt = new Array(blockCount);  // ciphertext as array of strings

  for (var b=0; b<blockCount; b++) {
    // set counter (block #) in last 8 bytes of counter block (leaving nonce in 1st 8 bytes)
    // done in two stages for 32-bit ops: using two words allows us to go past 2^32 blocks (68GB)
    for (var c=0; c<4; c++) counterBlock[15-c] = (b >>> c*8) & 0xff;
    for (var c=0; c<4; c++) counterBlock[15-c-4] = (b/0x100000000 >>> c*8)

    var cipherCntr = Aes.cipher(counterBlock, keySchedule);  // -- encrypt counter block --

    // block size is reduced on final block
    var blockLength = b<blockCount-1 ? blockSize : (plaintext.length-1)%blockSize+1;
    var cipherChar = new Array(blockLength);

    for (var i=0; i<blockLength; i++) {  // -- xor plaintext with ciphered counter char-by-char --
      cipherChar[i] = cipherCntr[i] ^ plaintext.charCodeAt(b*blockSize+i);
      cipherChar[i] = String.fromCharCode(cipherChar[i]);
    }
    ciphertxt[b] = cipherChar.join('');
  }

  // Array.join is more efficient than repeated string concatenation in IE
  var ciphertext = ctrTxt + ciphertxt.join('');
  ciphertext = Base64.encode(ciphertext);  // encode in base64

  //alert((new Date()) - t);
  return ciphertext;
}

/**
 * Decrypt a text encrypted by AES in counter mode of operation
 *
 * @param {String} ciphertext Source text to be encrypted
 * @param {String} password   The password to use to generate a key
 * @param {Number} nBits      Number of bits to be used in the key (128, 192, or 256)
 * @returns {String}          Decrypted text
 */
Aes.Ctr.decrypt = function(ciphertext, password, nBits) {
  var blockSize = 16;  // block size fixed at 16 bytes / 128 bits (Nb=4) for AES
  if (!(nBits==128 || nBits==192 || nBits==256)) return '';  // standard allows 128/192/256 bit keys
  ciphertext = Base64.decode(ciphertext);
  password = Utf8.encode(password);
  //var t = new Date();  // timer

  // use AES to encrypt password (mirroring encrypt routine)
  var nBytes = nBits/8;  // no bytes in key
  var pwBytes = new Array(nBytes);
  for (var i=0; i<nBytes; i++) {
    pwBytes[i] = isNaN(password.charCodeAt(i)) ? 0 : password.charCodeAt(i);
  }
  var key = Aes.cipher(pwBytes, Aes.keyExpansion(pwBytes));
  key = key.concat(key.slice(0, nBytes-16));  // expand key to 16/24/32 bytes long

  // recover nonce from 1st 8 bytes of ciphertext
  var counterBlock = new Array(8);
  ctrTxt = ciphertext.slice(0, 8);
  for (var i=0; i<8; i++) counterBlock[i] = ctrTxt.charCodeAt(i);

  // generate key schedule
  var keySchedule = Aes.keyExpansion(key);

  // separate ciphertext into blocks (skipping past initial 8 bytes)
  var nBlocks = Math.ceil((ciphertext.length-8) / blockSize);
  var ct = new Array(nBlocks);
  for (var b=0; b<nBlocks; b++) ct[b] = ciphertext.slice(8+b*blockSize, 8+b*blockSize+blockSize);
  ciphertext = ct;  // ciphertext is now array of block-length strings

  // plaintext will get generated block-by-block into array of block-length strings
  var plaintxt = new Array(ciphertext.length);

  for (var b=0; b<nBlocks; b++) {
    // set counter (block #) in last 8 bytes of counter block (leaving nonce in 1st 8 bytes)
    for (var c=0; c<4; c++) counterBlock[15-c] = ((b) >>> c*8) & 0xff;
    for (var c=0; c<4; c++) counterBlock[15-c-4] = (((b+1)/0x100000000-1) >>> c*8) & 0xff;

    var cipherCntr = Aes.cipher(counterBlock, keySchedule);  // encrypt counter block

    var plaintxtByte = new Array(ciphertext[b].length);
    for (var i=0; i<ciphertext[b].length; i++) {
      // -- xor plaintxt with ciphered counter byte-by-byte --
      plaintxtByte[i] = cipherCntr[i] ^ ciphertext[b].charCodeAt(i);
      plaintxtByte[i] = String.fromCharCode(plaintxtByte[i]);
    }
    plaintxt[b] = plaintxtByte.join('');
  }

  // join array of blocks into single plaintext string
  var plaintext = plaintxt.join('');
  plaintext = Utf8.decode(plaintext);  // decode from UTF8 back to Unicode multi-byte chars

  //alert((new Date()) - t);
  return plaintext;
}


/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -  */
/*  Base64 class: Base 64 encoding / decoding (c) Chris Veness 2002-2012                          */
/*    note: depends on Utf8 class                                                                 */
/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -  */

var Base64 = {};  // Base64 namespace

Base64.code = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";

/**
 * Encode string into Base64, as defined by RFC 4648 [http://tools.ietf.org/html/rfc4648]
 * (instance method extending String object). As per RFC 4648, no newlines are added.
 *
 * @param {String} str The string to be encoded as base-64
 * @param {Boolean} [utf8encode=false] Flag to indicate whether str is Unicode string to be encoded
 *   to UTF8 before conversion to base64; otherwise string is assumed to be 8-bit characters
 * @returns {String} Base64-encoded string
 */
Base64.encode = function(str, utf8encode) {  // http://tools.ietf.org/html/rfc4648
  utf8encode =  (typeof utf8encode == 'undefined') ? false : utf8encode;
  var o1, o2, o3, bits, h1, h2, h3, h4, e=[], pad = '', c, plain, coded;
  var b64 = Base64.code;

  plain = utf8encode ? str.encodeUTF8() : str;

  c = plain.length % 3;  // pad string to length of multiple of 3
  if (c > 0) { while (c++ < 3) { pad += '='; plain += '\0'; } }
  // note: doing padding here saves us doing special-case packing for trailing 1 or 2 chars

  for (c=0; c<plain.length; c+=3) {  // pack three octets into four hexets
    o1 = plain.charCodeAt(c);
    o2 = plain.charCodeAt(c+1);
    o3 = plain.charCodeAt(c+2);

    bits = o1<<16 | o2<<8 | o3;

    h1 = bits>>18 & 0x3f;
    h2 = bits>>12 & 0x3f;
    h3 = bits>>6 & 0x3f;
    h4 = bits & 0x3f;

    // use hextets to index into code string
    e[c/3] = b64.charAt(h1) + b64.charAt(h2) + b64.charAt(h3) + b64.charAt(h4);
  }
  coded = e.join('');  // join() is far faster than repeated string concatenation in IE

  // replace 'A's from padded nulls with '='s
  coded = coded.slice(0, coded.length-pad.length) + pad;

  return coded;
}

/**
 * Decode string from Base64, as defined by RFC 4648 [http://tools.ietf.org/html/rfc4648]
 * (instance method extending String object). As per RFC 4648, newlines are not catered for.
 *
 * @param {String} str The string to be decoded from base-64
 * @param {Boolean} [utf8decode=false] Flag to indicate whether str is Unicode string to be decoded
 *   from UTF8 after conversion from base64
 * @returns {String} decoded string
 */
Base64.decode = function(str, utf8decode) {
  utf8decode =  (typeof utf8decode == 'undefined') ? false : utf8decode;
  var o1, o2, o3, h1, h2, h3, h4, bits, d=[], plain, coded;
  var b64 = Base64.code;

  coded = utf8decode ? str.decodeUTF8() : str;


  for (var c=0; c<coded.length; c+=4) {  // unpack four hexets into three octets
    h1 = b64.indexOf(coded.charAt(c));
    h2 = b64.indexOf(coded.charAt(c+1));
    h3 = b64.indexOf(coded.charAt(c+2));
    h4 = b64.indexOf(coded.charAt(c+3));

    bits = h1<<18 | h2<<12 | h3<<6 | h4;

    o1 = bits>>>16 & 0xff;
    o2 = bits>>>8 & 0xff;
    o3 = bits & 0xff;

    d[c/4] = String.fromCharCode(o1, o2, o3);
    // check for padding
    if (h4 == 0x40) d[c/4] = String.fromCharCode(o1, o2);
    if (h3 == 0x40) d[c/4] = String.fromCharCode(o1);
  }
  plain = d.join('');  // join() is far faster than repeated string concatenation in IE

  return utf8decode ? plain.decodeUTF8() : plain;
}


/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -  */
/*  Utf8 class: encode / decode between multi-byte Unicode characters and UTF-8 multiple          */
/*              single-byte character encoding (c) Chris Veness 2002-2012                         */
/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -  */

var Utf8 = {};  // Utf8 namespace

/**
 * Encode multi-byte Unicode string into utf-8 multiple single-byte characters
 * (BMP / basic multilingual plane only)
 *
 * Chars in range U+0080 - U+07FF are encoded in 2 chars, U+0800 - U+FFFF in 3 chars
 *
 * @param {String} strUni Unicode string to be encoded as UTF-8
 * @returns {String} encoded string
 */
Utf8.encode = function(strUni) {
  // use regular expressions & String.replace callback function for better efficiency
  // than procedural approaches
  var strUtf = strUni.replace(
      /[\u0080-\u07ff]/g,  // U+0080 - U+07FF => 2 bytes 110yyyyy, 10zzzzzz
      function(c) {
        var cc = c.charCodeAt(0);
        return String.fromCharCode(0xc0 | cc>>6, 0x80 | cc&0x3f); }
    );
  strUtf = strUtf.replace(
      /[\u0800-\uffff]/g,  // U+0800 - U+FFFF => 3 bytes 1110xxxx, 10yyyyyy, 10zzzzzz
      function(c) {
        var cc = c.charCodeAt(0);
        return String.fromCharCode(0xe0 | cc>>12, 0x80 | cc>>6&0x3F, 0x80 | cc&0x3f); }
    );
  return strUtf;
}

/**
 * Decode utf-8 encoded string back into multi-byte Unicode characters
 *
 * @param {String} strUtf UTF-8 string to be decoded back to Unicode
 * @returns {String} decoded string
 */
Utf8.decode = function(strUtf) {
  // note: decode 3-byte chars first as decoded 2-byte strings could appear to be 3-byte char!
  var strUni = strUtf.replace(
      /[\u00e0-\u00ef][\u0080-\u00bf][\u0080-\u00bf]/g,  // 3-byte chars
      function(c) {  // (note parentheses for precence)
        var cc = ((c.charCodeAt(0)&0x0f)<<12) | ((c.charCodeAt(1)&0x3f)<<6) | ( c.charCodeAt(2)&0x3f);
        return String.fromCharCode(cc); }
    );
  strUni = strUni.replace(
      /[\u00c0-\u00df][\u0080-\u00bf]/g,                 // 2-byte chars
      function(c) {  // (note parentheses for precence)
        var cc = (c.charCodeAt(0)&0x1f)<<6 | c.charCodeAt(1)&0x3f;
        return String.fromCharCode(cc); }
    );
  return strUni;
}

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -  */
]===]
end	 -- GetAesJs

function getInfoViewerJS()
return [===[
var URL_PART   = './data_request';
var TIME_OUT_1 = 500;   // start up delay
var TIME_OUT_2 = 5000;  // run delay
var startLine  = 1;
var tail       = true;
var lastTimeVal = 0;
var lastTimeValValid = false;
var numInvalidLines = 0;
var MAX_INVALID_LINES = 3;
var SMALL_GAP_DELTA = 30;   // ms
var LARGE_GAP_DELTA = 1000; // ms

var id  = null;  // the id of the plugin
var app = null;

function parseParms()
{
    // get the URL and attempt to split it
    var urlParms = window.location.href.toLowerCase();
    urlParms = urlParms.split("?");

    // did the URL contain any parameters?
    if (urlParms.length > 1)
    {
        // get the parm(s) and attempt to split them
        var parms = urlParms[1].split("&");

        // for all the key value pairs
        for (var i=0; i<parms.length; i++)
        {
            // get the key value pairs and attempt to split them up
            var keyValue = parms[i].split("=");

            // the parms must come in key value pairs else the url is malformed
            if (keyValue.length != 2)
               break;

            // is this the id parameter?
            if (keyValue[0] == 'id')
               id = keyValue[1];

            // is this the application parameter?
            if (keyValue[0] == 'app')
               app = keyValue[1];
       }
    }
}

function parseXML(string)
{
	var xmlDoc;

	if (window.DOMParser) {
  		var parser=new DOMParser();
  		xmlDoc=parser.parseFromString(string,"text/xml");
  	}
	else // Internet Explorer
  	{
  		xmlDoc=new ActiveXObject("Microsoft.XMLDOM");
  		xmlDoc.async=false;
  		xmlDoc.loadXML(string);
  	}
	return(xmlDoc);
}

function insertTimeGaps(lines)
{
	var startLine = true;
 	for (var elem = lines.firstChild; elem != null; elem=elem.nextSibling) {
		if (elem.nodeType != 1) {
			// console.log("Unexpected element node type: "+elem.nodeType);
			return;
		}
		if (elem.tagName.toLowerCase() === 'br') {
		    startLine = true;
		}
	    else if (startLine) {
			if (elem.tagName.toLowerCase() !== 'span') {
				console.log("Unexpected element tag: "+elem.tagName);
				return;
			}
			startLine = false;
			if (elem.firstChild != null) {
				if (elem.firstChild.nodeType != 3) {
					console.log("Unexpected child node type: "+elem.firstChild.nodeType);
					return;
				}
				var text = elem.firstChild.nodeValue;
				var d = /^\d+\s+(\d+)\/(\d+)\/(\d+) (\d+):(\d+):(\d+)\.(\d+)\s/.exec(text);
				if (d != null) {
					numInvalidLines = 0;
				    var timeVal = (new Date(parseInt(d[3],10)+2000,d[1],d[2],d[4],d[5],d[6],d[7])).valueOf();
					if (lastTimeValValid) {
						var delta = timeVal - lastTimeVal;
						if (delta >= LARGE_GAP_DELTA) {
							var largeGap = document.createElement('DIV');
							largeGap.setAttribute("class","gap");
							largeGap.setAttribute("contenteditable","true");
							largeGap.innerHTML = "<br/><br/><br/><br/><br/>";
							lines.insertBefore(largeGap,elem);
						}
						else if (delta >= SMALL_GAP_DELTA) {
							var smallGap = document.createElement('DIV');
							smallGap.setAttribute("class","gap");
							smallGap.setAttribute("contenteditable","true");
							smallGap.innerHTML = "<br/>";
							lines.insertBefore(smallGap,elem);
						}
					}
					lastTimeValValid = true;
					lastTimeVal = timeVal;
				}
				else {
					numInvalidLines += 1;
					if (numInvalidLines > MAX_INVALID_LINES) {
						lastTimeValValid = false;
					}
				}
			}
		}
	}
}

var timeout	= 500;
var closetimer	= 0;
var ddmenuitem	= 0;

// open hidden layer
function mopen(id)
{
	// cancel close timer
	mcancelclosetime();

	// close old layer
	if(ddmenuitem) ddmenuitem.style.visibility = 'hidden';

	// get new layer and show it
	ddmenuitem = document.getElementById(id);
	ddmenuitem.style.visibility = 'visible';

}
// close showed layer
function mclose()
{
	if(ddmenuitem) ddmenuitem.style.visibility = 'hidden';
}

// go close timer
function mclosetime()
{
	closetimer = window.setTimeout(mclose, timeout);
}

// cancel close timer
function mcancelclosetime()
{
	if(closetimer)
	{
		window.clearTimeout(closetimer);
		closetimer = null;
	}
}

// close layer when click-out
document.onclick = mclose;

scrollBarWidth = null;
function getScrollbarWidth() {
	if (scrollBarWidth == null) {
	    var outer = document.createElement("div");
	    outer.style.visibility = "hidden";
	    outer.style.width = "100px";
	    outer.style.msOverflowStyle = "scrollbar"; // needed for WinJS apps
	    document.body.appendChild(outer);
	    var widthNoScroll = outer.offsetWidth;
	    outer.style.overflow = "scroll";
	    var inner = document.createElement("div");
	    inner.style.width = "100%";
	    outer.appendChild(inner);
	    var widthWithScroll = inner.offsetWidth;
	    outer.parentNode.removeChild(outer);
	    scrollBarWidth = widthNoScroll - widthWithScroll;
	}
	return scrollBarWidth;
}

function animateScroll(from,to,time) {
    var start = null;
	var keepgoing = true;
	var doframe = function(timestamp) {
		var step = 0;
		if (start == null) {
			start = timestamp
		} else {
			step = (timestamp - start) / time;
		}
		if (step >= 1) {
			step = 1
			keepgoing = false;
		}
		var step2 = Math.pow((1 - Math.cos(step * Math.PI))/2,0.6)
        window.scrollTo(0,from+step2*(to-from));
		if (keepgoing) {
			window.requestAnimationFrame(doframe)
		}
	}
	window.requestAnimationFrame(doframe)
}

function animate(elem,style,unit,from,to,time,prop) {
    if( !elem) return;
    var start = null;
	var keepgoing = true;
	var doframe = function(timestamp) {
		var step = 0;
		if (start == null) {
			start = timestamp
		} else {
			step = (timestamp - start) / time;
		}
		if (step >= 1) {
			step = 1
			keepgoing = false;
		}
		var step2 = Math.pow((1 - Math.cos(step * Math.PI))/2,0.6)
        if (prop) {
            elem[style] = (from+step2*(to-from))+unit;
        } else {
            elem.style[style] = (from+step2*(to-from))+unit;
        }
		if (keepgoing) {
			window.requestAnimationFrame(doframe)
		}
	}
	window.requestAnimationFrame(doframe)
}

function oldanimate(elem,style,unit,from,to,time,prop) {
    if( !elem) return;
    var start = new Date().getTime(),
        timer = setInterval(function() {
            var step = Math.min(1,(new Date().getTime()-start)/time);
			var step2 = math.pow((1 - math.cos(step * math.PI))/2,1)
            if (prop) {
                elem[style] = (from+step2*(to-from))+unit;
            } else {
                elem.style[style] = (from+step2*(to-from))+unit;
            }
            if( step == 1) clearInterval(timer);
        },30);
    elem.style[style] = from+unit;
}

firstChunk = true;
// This handles both onSuccess and onFailure
function logCallBack(response)
{
    var respXML = response.responseXML;
	if (!respXML) {
		// July 2013 - Mios remote server returns content-type:text/html even though vera responded with content-type:text/xml
		respXML = parseXML(response.responseText);
	}
    var retVal  = new Object();

    if (respXML && respXML.firstChild) {
        var resp = respXML.firstChild;
        while (resp) {
            if (resp.nodeName == 'ajax-response') {
                break;
            }
            resp = resp.nextSibling;
        }
        if (resp) {
            var attributes = resp.attributes;
            for (var i = 0; i < attributes.length; i++) {
                var attr = attributes.item(i);
                retVal[attr.name] = attr.value;
            }

            var child = resp.firstChild;
            while (child) {
                if (child.nodeName == '#cdata-section') {
                    retVal.data = child.data;
                    break;
                }
                child = child.nextSibling;
            }
        }
        if ((retVal.startLine === undefined) || (retVal.data === undefined)) {
            retVal.startLine = 1;
            retVal.data = 'Info Viewer ajax error - possibly malformed XML received: '+response.responseText;
        }
    }
    else {
        retVal.startLine = 1;
        retVal.data = 'Info Viewer ajax error - server status is: '+response.status;
    }

    if (retVal.startLine.length > 0)
    {
        startLine = parseInt(retVal.startLine,10);
        if (isNaN(startLine)) startLine = 1;
    }

    if (retVal.data.length > 0) {
		var windowHeight = window.innerHeight-60;
        var newLines = document.createElement('DIV');
        newLines.innerHTML = retVal.data;
		insertTimeGaps(newLines);
		ZShark(newLines);
		var scrollArea = document.getElementById('scrollArea');
		var log = document.getElementById('log');
		var wasNewScroll = scrollArea.scrollHeight-windowHeight-60+getScrollbarWidth();
		var oldScroll = window.pageYOffset || document.documentElement.scrollTop;
		console.log("wasNewScroll="+wasNewScroll+" oldScroll="+oldScroll+" diff="+(wasNewScroll-oldScroll)+" windowHeight="+windowHeight);
        log.insertBefore(newLines, log.lastChild);  // insert before bottomDummy.
		var animateTime = 2000;
		var newScroll = scrollArea.scrollHeight-windowHeight-60+getScrollbarWidth();
		if (newScroll - oldScroll < windowHeight) {
			animateTime = 2000 * (newScroll - oldScroll) / windowHeight;
		   	if (animateTime < 1) {
				animateTime = 1;
			}
		}
		// console.log("newScroll="+newScroll+ " scrollDelta="+(newScroll-oldScroll)+" animateTime="+animateTime);
		if (wasNewScroll <= oldScroll+1 || firstChunk) {
			animateScroll(oldScroll, newScroll, animateTime);
		}
		firstChunk = false;
    }

    window.setTimeout(refreshLog, TIME_OUT_2);
}

function clearLog()
{
	var log = document.getElementById('log');
	var dummy = log.lastChild;
	while (log.firstChild != dummy) {
    	log.removeChild(log.firstChild);
	}
}

function getLog(args, callBack)
{
   args.id = id;
   args.random = Math.random();

   ajaxRequest(URL_PART, args, callBack);
}

function refreshLog() {
    if (! tail) {
        window.setTimeout(refreshLog, TIME_OUT_1);
        return;
    }

    getLog({fnc: 'getLog', app: app, startLine: startLine}, logCallBack);
}

function stopRefresh() {
    tail = false;
    var pause = document.getElementById("pause-img");
    pause.style.display = 'none';
}

function resumeRefresh() {
    var pause = document.getElementById("pause-img");
    pause.style.display = 'inline';
    tail = true;
}

function startUp() {
   startLine = 1;
   tail      = true;

   parseParms();
   if ((id !== undefined) && (app !== undefined)) refreshLog();
}

// execute this
window.onload = startUp;

]===]
end	-- getInfoViewerJS

function GetZSharkJs()
return [===[
use_candystripe = true;
use_boxArt = true;
Key0 = false;

if(!Array.isArray) {
  Array.isArray = function (vArg) {
    return Object.prototype.toString.call(vArg) === "[object Array]";
  };
}

function ZShark(lines)
{
	var startLine = true;
	var interp = null;
	var addSpaces = 0;
	var startPos = 32;
 	for (var elem = lines.firstChild; elem != null; elem=elem.nextSibling) {
		if (elem.nodeType == 1) {
			if (elem.tagName.toLowerCase() === 'br') {
			    startLine = true;
				if (interp != null) {
					lines.insertBefore(interp,elem.nextSibling);
					elem = interp;
					interp = null;
				}
			}
		    else if (startLine) {
				if (elem.tagName.toLowerCase() == 'span') {
					startLine = false;
					if (elem.firstChild != null) {
						if (elem.firstChild.nodeType != 3) {
							console.log("Unexpected child node type: "+elem.firstChild.nodeType);
							return;
						}
						var text = elem.firstChild.nodeValue;
						var d = /^(4[12])\s+\d+\/\d+\/\d+ \d+:\d+:\d+\.\d+\s+(0x[ xX0-9a-fA-F]+) \(/.exec(text);
						text = expandTabs(text);
						elem.firstChild.nodeValue = text;
						if (d != null) {
							var arr = d[2].split(" ");
							var values = [];
							var positions = [];
							var startPosition = startPos;
							for (var i = 0; i < arr.length; i++) {
								var hex = arr[i];
								values.push(parseInt(hex, 0));
								positions.push(startPosition + hex.length - 1);
								startPosition += hex.length + 1;
							}
							annotations = [];
							try {
								var sending = text.charAt(1) == "1";
								var textChanged = false;
								DecryptStart = 0;
								DecryptLength = 0;
						   		interpretZWave(sending, values);
								if (DecryptLength > 0) {
									var addedZeroPad = 0;
									for (i = DecryptStart; i < values.length; ++i) {
										positions[i] += addedZeroPad;
										if (i < DecryptStart + DecryptLength) {
											if (positions[i] - positions[i-1] < 5) {
												text = text.substr(0, positions[i]) + "0" + text.substr(positions[i]);
												textChanged = true;
												positions[i]++
												addedZeroPad++;
											}
										}
									}
								}
								var obj = formatAnnotations(values, positions, annotations, sending);
								interp = obj.interp;
								addSpaces = obj.addSpaces;
								if (addSpaces > 0) {
								    text = text.substr(0, startPos) + repeatString(" ", addSpaces) + text.substr(startPos);
									textChanged = true;
								}
								if (textChanged) {
									elem.firstChild.nodeValue = text;
								}
							}
							catch(e) {
								console.log("Exception:" + e.name + ": " + e.message);
								if (e["stack"] != undefined) {
									console.log(e["stack"]);
								}
							}
 						} // d != null
					} // firstChild != null
				} // span
			} // startline
		} // nodeType == 1
		else {
			console.log("Unexpected element node type: "+elem.nodeType);
		}
	} // for
} // ZShark

function repeatString(c, len) {
	var s = ""
	for (var i = 0; i < len; ++i) {
		s += c;
	}
	return s;
}

function escapeHtml(unsafe) {
	return unsafe
         .replace(/&/g, "&amp;")
         .replace(/</g, "&lt;")
         .replace(/>/g, "&gt;")
         .replace(/"/g, "&quot;")
         .replace(/'/g, "&#039;");
}

function addTextAnnotation(text, startIndex, endIndex, allowOverlap)
{
	addHtmlAnnotation(escapeHtml(text), startIndex, endIndex, allowOverlap);
}

function addHtmlAnnotation(html, startIndex, endIndex, allowOverlap)
{
	var temp = document.createElement('SPAN');
	temp.innerHTML = html;
	var text = temp.textContent || temp.innerText;
	if (! endIndex) {
		endIndex = startIndex;
	}
	annotations.push({html: html, text: text, len: text.length, startIndex: startIndex, endIndex: endIndex, allowOverlap: allowOverlap, pushOrder: annotations.length});
}

function addDummyAnnotation(startIndex, endIndex)
{
	if (! endIndex) {
		endIndex = startIndex;
	}
	annotations.push({isDummy: true, startIndex: startIndex, endIndex: endIndex, allowOverlap: true, pushOrder: annotations.length});
}


function appendLastHtmlAnnotation(html)
{
	var annotation = annotations.pop();
	var temp = document.createElement('SPAN');
	temp.innerHTML = annotation.html + html;
	var text = temp.textContent || temp.innerText;
	annotations.push({html: temp.innerHTML, text: text, len: text.length, startIndex: annotation.startIndex, endIndex: annotation.endIndex});
}

function expandTabs(str)
{
	var pos = 0;
	var result = "";
	for (var i = 0; i < str.length; ++i) {
		var c = str.charAt(i);
		if (c == "\t") {
			do {
				result += " ";
				pos++;
			} while (pos % 8 != 0)
		}
		else {
			result += c;
			pos++;
		}
	}
	return result;
}

function formatAnnotations(values, positions, annotations, sending)
{
	annotations.sort(function(a,b) {
		if ( a.startIndex - b.startIndex) {
			return a.startIndex - b.startIndex;
		}
		return a.pushOrder - b.pushOrder;
	});
	var prevIndex = -1;
	for (var i = 0; i < annotations.length; ++i) {
		var a = annotations[i];
		if ((a.allowOverlap && a.startIndex < prevIndex) || (!a.allowOverlap && a.startIndex <= prevIndex) || a.endIndex < a.startIndex || a.endIndex >= values.length) {
			console.log("Invalid annotation index: html=" + a.html + " len=" + a.len + " startIndex=" + a.startIndex + " endIndex=" + a.endIndex + "prevIndex=" + prevIndex + "values.length=" + values.length);
			annotations.splice(i--,1);
			continue;
		}
		if (a.startIndex > prevIndex+1) {
			annotations.splice(i++,0,{html:"?<span style='color:Magenta;'>data</span>?", len:6, startIndex:prevIndex+1, endIndex:a.startIndex-1});
		}
		prevIndex = a.endIndex;
	}
	var candy = 0;
	annotations[0].candyStripe = candy;
	for (var i=1; i < annotations.length; ++i) {
		if (annotations[i].endIndex != annotations[i-1].endIndex) {
			candy = (candy + 1) % 8;
		}
		annotations[i].candyStripe = candy;
	}
	var addSpaces = 0;
	var moreSpaces;
	do {
		moreSpaces = 0;
		for (var i = 0; i < annotations.length; ++i) {
		    var annotationPos = positions[0] - 3;
			var a = annotations[i];
			if (a.isDummy) {
				continue;
			}
			var startPos = positions[a.startIndex];
			var endPos = positions[a.endIndex];
			var midPos;
			if (startPos < endPos) {
				if (values[a.startIndex] >= 16 || (a.startIndex >= DecryptStart && a.endIndex < DecryptStart+DecryptLength)) {
					startPos -= 3;
				}
				else {
					startPos -= 2;
				}
				midPos = (startPos + endPos) >> 1;
			}
			else {
				midPos = startPos;
			}
			if (i > 0 && !annotations[i-1].isDummy && a.text.substring(0,6) == annotations[i-1].text.substring(0,6)) { // Allign related annotations ex. "Node: "
				var t = annotations[i-1].annotationPosition - annotations[i-1].len + a.len;
				if (annotationPos > t) {
					annotationPos = t;
				}
			}
			if (a.len > annotationPos) {
				annotationPos = a.len;
			}
			if (i > 0 && endPos > startPos) {
				if (annotationPos > midPos-1) {
					midPos = annotationPos+1;
					if (midPos > endPos-1) {
						moreSpaces = midPos - (endPos-1);
						break;
					}
				}
			} else if (annotationPos > startPos - 1) {
				moreSpaces = annotationPos + 1 - startPos;
				break;
			}
			a.annotationPosition = annotationPos;
			a.startPosition = startPos;
			a.endPosition = endPos;
			a.midPosition = midPos;
		}
		addSpaces += moreSpaces;
		if (moreSpaces > 0) {
			for (var i = 0; i < positions.length; ++i) {
				positions[i] += moreSpaces;
			}
		}
	} while (moreSpaces > 0)
	var interp = document.createElement('DIV');
	if (sending) {
		interp.setAttribute("class","interp_send");
	}
	else {
		interp.setAttribute("class","interp_receive");
	}
	var html = "";
	for (var i = 0; i < annotations.length; ++i) {
		var a = annotations[i];
		if (a.isDummy) {
			continue;
		}
		var t = repeatString(" ", a.annotationPosition-a.len) + a.html + " ";
		var position = a.annotationPosition + 1;
		for (var j = i; j < annotations.length; ++j) {
			var b = annotations[j];
			if (b.isDummy) {
				continue;
			}
			if (use_candystripe) {
				t += "<span class='zcs"+b.candyStripe+"'>";
			}
			var bend = b.midPosition;
			var rangeRow = (b.startIndex >= DecryptStart && b.endIndex < DecryptStart+DecryptLength) ? 1 : 0;
			if (rangeRow == 1 && i == 0 && b.endPosition == b.startPosition) {
				bend = b.startPosition - 3;
			}
			else if (i <= rangeRow) {
				bend = b.startPosition;
			}
			if (j == i) {
				for (; position < bend; ++position) {
					t += use_boxArt ? "&#x2500" : "-";
				}
			}
			else {
				if (position >= bend) {
					if (use_candystripe) {
						t += "</span>";
					}
					continue;
				}
				for (; position < bend; ++position) {
					t += " ";
				}
			}
			if (rangeRow > 0) {
				if (i == 0) {
					for (var k = b.startIndex; k <= b.endIndex; ++k) {
						 t += "0x";
						 if (values[k] < 16) {
							t += "0"
						 }
						 t += values[k].toString(16);
						 position +=4;
						 if (k < b.endIndex) {
							t += " ";
							position++;
						 }
					}
					if (use_candystripe) {
						t += "</span>";
					}
					continue;
				}
			}
			if (i == rangeRow && (b.startPosition < b.endPosition)) {
				if (use_boxArt) {
					t += position == b.midPosition ? "&#x251C" : "&#x2514"; ++position;
					for (; position < b.endPosition; ++position) {
						t += position == b.midPosition ? "&#x252C" : "&#x2500";
					}
					t += position == b.midPosition ? "&#x2524" : "&#x2518"; ++position;
				}
				else {
					t += "\\"; ++position;
					for (; position < b.endPosition; ++position) {
						t += "_"
					}
					t += "/"; ++position;
				}
			}
			else {
				if (j == i) {
					if (use_boxArt) {
						if (i < annotations.length-1 && annotations[i+1].endPosition == a.endPosition) {
							t += "&#x2524";
						} else {
							t += "&#x2518";
						}
					} else {
						t += "+";
					}
					++position;
				} else {
					t += use_boxArt ? "&#x2502" : "|"; ++position
				}
			}
			if (use_candystripe) {
				t += "</span>";
			}
		}
		html += t + "<br/>";
	}
	interp.innerHTML = html;
	return {interp: interp, addSpaces: addSpaces};
}

function byteToHex(d) {
    var hex = Number(d).toString(16).toUpperCase();
	if (d < 16) {
		hex = "0" + hex;
	}
	return "0x" + hex;
}

function bitFlagHtml(bitNames, value)
{
	if (value == 0) {
		return "(none)";
	}
	var mask = 1;
	var i = 0;
	var txt = ""
	while (value != 0 && i < bitNames.length) {
		if ((value & mask) && bitNames[i]) {
			txt += bitNames[i];
			value &= ~mask;
			if (value != 0) {
				txt += " | ";
			}
		}
		mask <<= 1;
		i++;
	}
	if (value != 0) {
		txt += "<span style='color:Magenta;'>Reserved bits : " + byteToHex(value) + "</span>"
	}
	return txt;
}

function getNodeIdHtml(nodeId)
{
	if (nodeId == 0) {
	  return ": <span style='color:#FFFF00;font-weight:bold;'>*None*</span>";
	}
	var node = ZWaveNodeList[nodeId];
	if (node == undefined) {
	  return "<span style='color:Magenta;'>Unknown node ID: " + nodeId + "</span>";
	}
	else {
	  return "Device " + node.deviceId + "=<span style='color:#FFD800;font-weight:bold;'>" +  escapeHtml(node.name)+"</span>";
	}
}

function interpretZWave(sending, values)
{
	var state = 0;
	var packetLength = values.length;
	var length;
	var dataLength;
	var classData;
	var commands;
	var commandData;
	var isRequest;
	var arrayLength = 0;
	SourceNode = 1;
	DestinationNode = 1;
	MACBuffer = [];
	for (var index = 0; index < packetLength; ++index) {
		var v = values[index];
		switch(state) {
			case 0:	 // Byte 0
				switch(v) {
					case 0x01: addTextAnnotation("SOF - Start Of Frame", index); state = 1; break;
					case 0x06: addTextAnnotation("ACK - Acknowledge", index); break;
					case 0x15: addHtmlAnnotation("<span style='color:Orange;'>NAK</span> - No Acknowledge", index); break;
					case 0x18: addHtmlAnnotation("<span style='color:Red;'>CAN</span> - Cancel", index); break;
					default:   addHtmlAnnotation("<span style='color:Magenta;'>Unknown start of packet: " + v + "</span>", index); break;
					break;
				}
				break;
			case 1:	 // Byte 1 = length
				length = v;
				state = 2;
				if (length > values.length - 2) {
					addHtmlAnnotation("<span style='color:Magenta;'>Packet length too long = " + length + "&gt; " + (values.length - 2) + "</span>", index);
					return;
				}
				else if (length == 0) {
					addHtmlAnnotation("<span style='color:Magenta;'>?Packet ength is 0?</span>", index);
					return;
				}
				addTextAnnotation("length = " + length, index);
				var checksum = 0xFF;
				for (var i = 0; i < length; ++i) {
					checksum = checksum ^ values[index + i];
				}
				if (checksum == values[index + length]) {
					addHtmlAnnotation("Checksum <span style='color:LawnGreen;'>OK</span>", index + length);
					packetLength = index + length;
					state = 2;
				}
				else {
					addHtmlAnnotation("Checksum <span style='color:Red;'>WRONG</span> should be " + byteToHex(checksum), index + length);
					return;
				}
				break;
			case 2:	 // request/response
				switch(v) {
					case 0x00: addTextAnnotation("Request", index);  isRequest = true;  state = 3; break;
					case 0x01: addTextAnnotation("Response", index); isRequest = false; state = 3; break;
					default:   addHtmlAnnotation("<span style='color:Magenta;'>Unknown packet type: " + v + "</span>", index); return;
				}
				break;
			case 3:	 // FUNC_ID
				var funcID = funcIDTable[v];
				if (funcID == undefined) {
					addHtmlAnnotation("<span style='color:Magenta;'>Unknown funtion ID: " + byteToHex(v) + "</span>", index); return;
				}
				else if (typeof(funcID) == "string") {
					addTextAnnotation(funcID,index);
					switch(v) {
					    case 0x04: /* FUNC_ID_APPLICATION_COMMAND_HANDLER */ state = 8; break;
						case 0x13: /* FUNC_ID_ZW_SEND_DATA */
							if (isRequest) {
								state = 6;
							} else {
								state = 15;
							}
							break;
						case 0x19: /* FUNC_ID_ZW_SEND_DATA_GENERIC */
							if (isRequest) {
								state = 12;
							} else {
								state = 15;
							}
							break;
					    default: return;
					}
				}
				else {
					addTextAnnotation(funcID[0], index);
					if (index < packetLength - 1) {
						HandleParameters(values, funcIDTable, funcID, index, packetLength, sending, isRequest);
					}
					return;
				}
				break;
			case 5:  // response FUNC_ID_ZW_SEND_DATA
				switch(v) {
					case 0x00: addHtmlAnnotation("TRANSMIT_COMPLETE_<span style='color:LawnGreen;'>OK</span>", index); break;
					case 0x01: addHtmlAnnotation("TRANSMIT_COMPLETE_<span style='color:Orange;'>NO_ACK</span>", index); break;
					case 0x02: addHtmlAnnotation("TRANSMIT_COMPLETE_<span style='color:Red;'>FAIL</span>", index); break;
					case 0x03: addHtmlAnnotation("TRANSMIT_COMPLETE_<span style='color:Orange;'>NOT_IDLE</span>", index); break;
					case 0x04: addHtmlAnnotation("TRANSMIT_COMPLETE_<span style='color:Orange;'>NOROUTE</span>", index); break;
					case 0x05: addHtmlAnnotation("TRANSMIT_COMPLETE_<span style='color:Red;'>HOP_0_FAIL</span>", index); break;
					case 0x06: addHtmlAnnotation("TRANSMIT_COMPLETE_<span style='color:Red;'>HOP_1_FAIL</span>", index); break;
					case 0x07: addHtmlAnnotation("TRANSMIT_COMPLETE_<span style='color:Red;'>HOP_2_FAIL</span>", index); break;
					case 0x08: addHtmlAnnotation("TRANSMIT_COMPLETE_<span style='color:Red;'>HOP_3_FAIL</span>", index); break;
					case 0x09: addHtmlAnnotation("TRANSMIT_COMPLETE_<span style='color:Red;'>HOP_4_FAIL</span>", index); break;
					default:   addHtmlAnnotation("<span style='color:Magenta;'>Unknown transmit complete: " + v + "</span>", index); return;
				}
				state = 14;
				break;

			case 6:  // request FUNC_ID_ZW_SEND_DATA node ID
				if (sending) {
					DestinationNode = v;
					addHtmlAnnotation(getNodeIdHtml(v), index);
					state = 7;
				}
				else {
					addTextAnnotation("Callback = " + v, index);
					state = 5;
				}
				break;

			case 7:  // request FUNC_ID_ZW_SEND_DATA data length
				dataLength = v;
				addTextAnnotation("Data length = " + dataLength, index);
				var xmitOptionsIndex = index + dataLength + 1;
				if (xmitOptionsIndex < packetLength) {
					var xmitOptions = values[xmitOptionsIndex]
					var xmitStr = "Xmit options = " + bitFlagHtml(["ACK", "LOW_POWER", "AUTO_ROUTE", , "DIRECT_ROUTE" ], xmitOptions);
					addHtmlAnnotation(xmitStr, xmitOptionsIndex);
				}
				if (xmitOptionsIndex + 1 < packetLength) {
					addTextAnnotation("Callback = " + values[xmitOptionsIndex + 1], xmitOptionsIndex + 1);
				}
				packetLength = xmitOptionsIndex;
				state = 11;
				break;

			case 8:  // FUNC_ID_APPLICATION_COMMAND_HANDLER receive status
				var html = "Receive Status";
				switch(v & 0xAC) {
					case 0x00: html += " SINGLE"; break;
					case 0x04: html += " BROAD"; break;
					case 0x08: html += " MULTI"; break;
					default: html = "<span style='color:Magenta;'>Unknown Receive Staus: " + v + "</span>"; v = 0; break;
				}
				if (v & 0x01) {
					html += " | ROUTED_BUSY";
				}
				if (v & 0x02) {
					html += " | LOW_POWER";
				}
				if (v & 0x10) {
					html += " | EXPLORE";
				}
				if (v & 0x40) {
					html += " | FOREIGN_FRAME";
				}
				addHtmlAnnotation(html, index);
				state = 9;
				break;

			case 9:  // FUNC_ID_APPLICATION_COMMAND_HANDLER node ID
				SourceNode = v;
				addHtmlAnnotation(getNodeIdHtml(v), index);
				state = 10;
				break;

			case 10:  // FUNC_ID_APPLICATION_COMMAND_HANDLER length
				dataLength = v;
				if (dataLength + index >= packetLength) {
					addHtmlAnnotation("<span style='color:Magenta;'>Data length too long: " + v + "</span>", index);
					return;
				}
				else {
					addTextAnnotation("Data length = " + dataLength, index);
				}
				state = 11;
				break;

			case 11: // Command_Class
				index = handleCommandClass(values, index, packetLength, "", sending, isRequest);
				return;

			case 12:  // request FUNC_ID_ZW_SEND_DATA_GENERIC node ID
				if (sending) {
					DestinationNode = v;
					addHtmlAnnotation(getNodeIdHtml(v), index);
					state = 13;
				}
				else {
					addTextAnnotation("Callback = " + v, index);
					state = 5;
				}
				break;

			case 13:  // request FUNC_ID_ZW_SEND_DATA_GENERIC data length
				dataLength = v;
				addTextAnnotation("Data length = " + dataLength, index);
				var xmitOptionsIndex = index + dataLength + 1;
				var ignoreRouteData = false;
				if (xmitOptionsIndex < packetLength) {
					var xmitOptions = values[xmitOptionsIndex]
					var xmitStr = "Xmit options = " + bitFlagHtml(["ACK", "LOW_POWER", "AUTO_ROUTE", , "DIRECT_ROUTE" ], xmitOptions);
					if (xmitOptions & 0x10) {  // DIRECT_ROUTE
						ignoreRouteData = true;
					}
					addHtmlAnnotation(xmitStr, xmitOptionsIndex);
				}
				if (xmitOptionsIndex + 5 < packetLength) {
					for (var j = 1; j <= 4; ++j) {
						if (values[xmitOptionsIndex + j] == 0) {
							ignoreRouteData = true;
						}
						if (ignoreRouteData) {
							addTextAnnotation("Routing data ignored" , xmitOptionsIndex + j, xmitOptionsIndex + 4 );
							break;
						}
						addHtmlAnnotation("Route through: " + getNodeIdHtml(values[xmitOptionsIndex + j]), xmitOptionsIndex + j, xmitOptionsIndex + j);
					}
					addTextAnnotation("Callback = " + values[xmitOptionsIndex + 5], xmitOptionsIndex + 5);
				}
				packetLength = xmitOptionsIndex;
				state = 11;
				break;

			case 14:  // SENDDATA with IMA txTime
				if (index <= packetLength-2) {
					addTextAnnotation("Tx Time = " + (values[index]*256 + values[index+1]) + " ms", index, index+1);
				}
				else {
					addHtmlAnnotation("<span style='color:Magenta;'>TxTime truncated:</span>", index);
				}
				return;
			case 15:  // response FUNC_ID_ZW_SEND_DATA, FUNC_ID_ZW_SEND_DATA_GENERIC
				switch(v) {
					case 0x00: addHtmlAnnotation("RetVal: <span style='color:Red;'>Transmit Queu Overflow</span>", index); break;
					case 0x01: addHtmlAnnotation("RetVal: OK", index); break;
					default:   addHtmlAnnotation("<span style='color:Magenta;'>Unknown RetVal: " + v + "</span>", index); return;
				}
				return;
			default:
				console.log("invalid state: " + state);
				return;
		}
	}
}

function handleCommandClass(values, index, length, prefix, sending, isRequest)
{
	var v = values[index];
	var classData = cmdClasses[values[index]];
	if (classData == undefined) {
		addHtmlAnnotation("<span style='color:Magenta;'>Unknown " + prefix + "command class: " + v + "</span>", index);
		return index;
	}
	else if (typeof(classData) == "string") {
		addTextAnnotation(prefix + classData, index);
		return index;
	}
	addTextAnnotation(prefix + classData[0], index);
	var commands = classData[1];
	if (index >= length - 1) {
		appendLastHtmlAnnotation(" <span style='color:Magenta;'>TRUNCATED</span>");
		return index;
	}
	index++;
	var command = commands[values[index]];
	if (command == undefined) {
		if (commands["*"] != undefined) {
			addTextAnnotation(commands["*"], index, length-1);
			return length-1;
		}
		else {
			addHtmlAnnotation("<span style='color:Magenta;'>Unknown command: " + values[index] + "</span>", index);
		}
		return index;
	}
	if (typeof(command) == "string") {
		addTextAnnotation(command, index);
		return index;
	}
	addTextAnnotation(command[0], index);
	if (command[1] == "sameAs") {
		if (command[3] == "Key0") {
			// commandName, "sameAs", command, "Key0" (current command clasee - Zero AES keys)
			Key0 = true;
			command = commands[command[2]];
		} else if (command[3] != undefined) {
			// commandName, "sameAs", commandClass, command
			classData = cmdClasses[command[2]];
			commands = classData[1];
			command = commands[command[3]];
		}
		else {
			// commandName, "sameAs", command (current command clasee)
			command = commands[command[2]];
		}
	}
	return HandleParameters(values, commands, command, index, length, sending, isRequest);
}

function HandleParameters(values, commands, command, index, length, sending, isRequest)
{
	var c = command[1];
	var startIndex = 1;
	if (typeof(c) == "object" && !Array.isArray(c)) {
		startIndex = 0;
		if (sending && isRequest && c["Send_Request"]) {
			command = c["Send_Request"];
		}
		else if (sending && !isRequest && c["Send_Response"]) {
			command = c["Send_Response"];
		}
		else if (!sending && isRequest && c["Receive_Request"]) {
			command = c["Receive_Request"];
		}
		else if (!sending && !isRequest && c["Receive_Response"]) {
			command = c["Receive_Response"];
		}
		else if (sending && c["Send"]) {
			command = c["Send"];
		}
		else if (!sending && c["Receive"]) {
			command = c["Receive"];
		}
		else if (isRequest && c["Request"]) {
			command = c["Request"];
		}
		else if (!isRequest && c["Response"]) {
			command = c["Response"];
		}
		else {
			console.log("Invalid Send/Receive/Request/Response qualifier");
			return index;
		}
	}
	for (var parameter = startIndex; command[parameter] != undefined; ++parameter) {
		var paramData = command[parameter];

		if (index >= length - 1) {
			if (paramData[2] != "Optional" && ((paramData[1] != "ARRAY" && paramData[1] != "STRING") || paramData[2] != 0)) {
				appendLastHtmlAnnotation(" <span style='color:Magenta;'>TRUNCATED</span>");
			}
			return index;
		}
		index++
		var paramName = paramData[0];
		var skipOpt = 1;
		if (paramData[1] == "Optional") {
			skipOpt = 2;
		}
		if (paramData[skipOpt] == "sameAs") {
			if (paramData[skipOpt + 3] != undefined) {
				// paramName, "sameAs", commandClass, command, paramNum
				paramData =  cmdClasses[paramData[skipOpt + 1]][1][paramData[skipOpt + 2]][paramData[skipOpt + 3]];
			}
			else if (paramData[skipOpt + 2] != undefined && commands != null) {
				// paramName, "sameAs", command, paramNum (current command class)
				paramData = commands[paramData[skipOpt + 1]][paramData[skipOpt + 2]];
			}
			else {
				// paramName, "sameAs", paramNum (current command class, current command)
				paramData = command[paramData[skipOpt + 1]];
			}
			if (paramData[1] != "Optional") {
				skipOpt = 1;
			}
		}
		index = handleParam(values, index, length, paramName, paramData, skipOpt, sending, isRequest);
	}
	return index;
}

function handleParam(values, index, length, paramName, paramData, paramIndex, sending, isRequest)
{
	var firstIndex = index;
	var v = values[index];
	var value;
	switch(paramData[paramIndex]) {
		case "BYTE":
			value = v;
			break;
		case "BYTE1234":
			if (index == length-1) {
				value = v;
			}
			else if (index == length-2) {
				value = (v << 8);
				value += values[++index];
			}
			else if (index == length-3) {
				value = (v << 16);
				value += (values[++index] << 8);
				value += values[++index];
			}
			else {
				value = (v << 24);
				value += (values[++index] << 16);
				value += (values[++index] << 8);
				value += values[++index];
			}
			break;
		case "WORD":
			if (index >= length-1) {
				addHtmlAnnotation(paramName + " = <span style='color:Magenta;'>Not enough data for WORD</span>", index, length-1);
				return length-1;
			}
			value = (v << 8);
			value += values[++index];
			break;
		case "WORD3":
			if (index >= length-2) {
				addHtmlAnnotation(paramName + " = <span style='color:Magenta;'>Not enough data for WORD3</span>", index, length-1);
				return length-1;
			}
			value = (v << 16);
			value += (values[++index] << 8);
			value += values[++index];
			break;
		case "DWORD":
			if (index >= length-3) {
				addHtmlAnnotation(paramName + " = <span style='color:Magenta;'>Not enough data for DWORD</span>", index, length-1);
				return length-1;
			}
			value = (v * 0x1000000);
			value += (values[++index] << 16);
			value += (values[++index] << 8);
			value += values[++index];
			break;
		case "ARRAY":
			var paramIndexOffset = 2;
			var arrayLength = paramData[paramIndex+1];
			if (arrayLength == "M") { // byte array terminated by marker
				var marker = paramData[paramIndex+2];
				paramIndexOffset = 3;
				arrayLength = length - index;
				for (var i = index; i < length; ++i) {
					if (values[i] == marker) {
						arrayLength = i- index;
						break;
					}
				}
			} else if (arrayLength == 0) { // Must be an array of byte-sized objects
				arrayLength = length - index;
			}
			else if (arrayLength < 0) { // Typically -1 for length followed by array
				arrayLength = values[index + arrayLength] + (arrayLength + 1);
			}
			var reduce = 0;
			if (paramData.length > paramIndex + paramIndexOffset) {
				reduce = Number(paramData[paramIndex + paramIndexOffset]);
			}
			if (reduce < 0 && reduce+arrayLength >= 0) { // Optional negative second parameter to reduce the array size by a fixed trailer size
				arrayLength += reduce;
				paramIndexOffset++;
			}
			if 	(paramIndex + paramIndexOffset >= paramData.length) {
				addTextAnnotation(paramName, index, index + arrayLength - 1);
				index += arrayLength;
			}
			else if (paramData[paramIndex + paramIndexOffset] == "NONCE") {
				nonce = values.slice(index,index+8);
				addTextAnnotation(paramName, index, index + arrayLength - 1);
				index += arrayLength;
			}
			else if (paramData[paramIndex + paramIndexOffset] == "IV") {
				var iv = values.slice(index,index+8);
				addTextAnnotation(paramName, index, index + arrayLength - 1);
				index += arrayLength;
				ExpandKeys();
				Decrypt(values, index, length - index - 9, iv, nonce);
			}
	   		else if (paramData[paramIndex + paramIndexOffset] == "EENCAP") {
				handleCommandClass(values, index, index+arrayLength, "Encrypted ", sending, isRequest);
			    return index + arrayLength - 1;
			}
			else if (paramData[paramIndex + paramIndexOffset] == "MAC") {
				var match = true;
				for (var i = 0; i < 8; ++i) {
					if (values[index+i] != MACBuffer[i]) {
						match = false;
						break;
					}
				}
				if (match) {
					addHtmlAnnotation(paramName+" <span style='color:LawnGreen;'>OK</span>", index, index + arrayLength - 1);
				}
				else {
					var annotation = paramName+" <span style='color:Red;'>WRONG</span> should be";
					for (var i = 0; i < 8; ++i) {
						annotation += " " +  byteToHex(MACBuffer[i]);
					}
					addHtmlAnnotation(annotation, index, index + arrayLength - 1);
				}
				index += arrayLength;
			}
			else {
			    for (var i = 1; i <= arrayLength; ++i) {
					if (index >= length) {
						appendLastHtmlAnnotation("<span style='color:Magenta;'>Not enough data for array element " + i + "</span>");
						return index;
					}
					index = handleParam(values, index, length, paramName + "[" + i + "]", paramData, paramIndex + paramIndexOffset, sending, isRequest) + 1;
				}
			}
			return index - 1;
			break;
		case "BITARRAY":
			var arrayLength = paramData[paramIndex+1];
			var arrayBase = paramData[paramIndex+2];
			if (arrayLength == 0) { // Must be an array of byte-sized objects
				arrayLength = length - index;
			}
			else if (arrayLength < 0) { // Typically -1 for length followed by array
				arrayLength = values[index + arrayLength];
			}
			if (index + arrayLength > length) {
				appendLastHtmlAnnotation("<span style='color:Magenta;'>Not enough data for array element " + i + "</span>");
				return index;
			}
			for (var i = 0; i < arrayLength; ++i) {
				if (values[index+i] == 0) {
					 addDummyAnnotation(index+i);
				}
				else {
					for (var j = 0; j < 8; ++j) {
						if (values[index+i] & (1 << j)) {
							var num = i*8 + j + arrayBase;
							HandleParamValue(values, index+i, index+i, length, paramName, paramData, paramIndex + 2, num, sending, isRequest, true);
						}
					}
				}
			}
			return index + arrayLength - 1;
		case "STRING":
			var str = paramName + " = ";
			var zchar = 0;
			var stringLength = paramData[2];
			if (stringLength == undefined || stringLength == 0) {
				stringLength = length - index;
			} else if (stringLength == "Z") {
				stringLength = 0;
				zchar = 1;
				while (values[index + stringLength] != 0) {
					if (index + stringLength >= length-1) {
						break;
					}
					++stringLength;
				}
				if (index+stringLength >= length-1) {
					zchar = 0;
				}
			} else if (stringLength < 0) {
				stringLength = values[index + stringLength];
			}
			if (index + stringLength > length) {
				str += "<span style='color:Magenta;'>Not enough data for STRING length " + stringLength + "</span>";
				stringLength = length - index;
			}
			str += "\"<span style='color:Gold;'>";
			for (var i = 0; i < stringLength; ++i) {
				v = values[index++];
				if (v < 32 || v >= 127 || v == 34) {
					switch(v) {
						case 0 : str += "\\0"; break;
						case 8 : str += "\\b"; break;
						case 9 : str += "\\t"; break;
						case 10: str += "\\n"; break;
						case 13: str += "\\r"; break;
						case 34: str += "\\\""; break;
						default: str += "\\x";
							if (v < 16) {
								str += "0";
							}
							str += v.toString(16).toUpperCase();
						break;
					}
				}
				else {
					str += escapeHtml(String.fromCharCode(v));
				}
			}
			str += "</span>\"";
			index = index - 1 + zchar;
			addHtmlAnnotation(str, firstIndex, index);
			return index;
			break;
		case "ENCAP":
			index = handleCommandClass(values, index, length, "Encapsulated ", sending, isRequest);
		    return index;
			break;
		case "LEN_ENCAP":
			var encapLength = v;
			if (index + encapLength >= length) {
				addHtmlAnnotation(paramName + " = " + "<span style='color:Magenta;'>Not enough data for command length "+ encapLength + "</span>", index);
				encapLength = length - index - 1;
			}
			else {
				addTextAnnotation("Command Length = " + encapLength, index);
			}
			if (encapLength > 0) {
				index = handleCommandClass(values, index + 1, encapLength, "Encapsulated ", sending, isRequest);
			}
			return index;
		default:
			console.log("Invalid parameter size: " +  paramData[paramIndex]);
			return index;
	}
	return HandleParamValue(values, firstIndex, index, length, paramName, paramData, paramIndex, value, sending, isRequest, false);
}

function HandleParamValue(values, firstIndex, index, length, paramName, paramData, paramIndex, value, sending, isRequest, allowOverlap)
{
	var paramType = paramData[paramIndex+1];
	if (paramType == "Optional") {
		paramIndex++;
		paramType = paramData[paramIndex+1];
	}
	if (paramType == undefined || paramType == "decimal") {
		addTextAnnotation(paramName + " = " + value, firstIndex, index, allowOverlap);
	}
	else if (paramType == "hex") {
		addTextAnnotation(paramName + " = 0x" + (value.toString(16)), firstIndex, index, allowOverlap);
	}
	else if (paramType == "ignore") { // Don't show value. Typically used for an array end marker
		addTextAnnotation(paramName, firstIndex, index, allowOverlap);
	}
	else if (paramType == "reserved") { // Flag a reserved value if not 0
		if (value == 0) {
			addTextAnnotation(paramName, firstIndex, index, allowOverlap);
		}
		else {
			addHtmlAnnotation("<span style='color:Magenta;'>" +	paramName + " = " + value + "</span>", firstIndex, index, allowOverlap);
		}
	}
	else if (paramType == "node") {
		addHtmlAnnotation(paramName + ": " + value + " " + getNodeIdHtml(value), firstIndex, index, allowOverlap);
	}
	else if (paramType == "enum") {
		var enumVal = paramData[paramIndex+2][value];
		var showValue = "";
		if (enumVal == undefined) {
			enumVal = paramData[paramIndex+2][-1];
			showValue = "(" + value + ")";
		}
		if (enumVal == undefined) {
			addHtmlAnnotation(paramName + " = <span style='color:Magenta;'>UNKNOWN ("+ value + ")</span>", firstIndex, index, allowOverlap);
		}
		else if (typeof(enumVal) == "string") {
			addTextAnnotation(paramName + " = " + enumVal + showValue, firstIndex, index, allowOverlap);
		}
		else {
			addTextAnnotation(paramName + " = " + enumVal[0] + showValue, firstIndex, index, allowOverlap);
			if (enumVal[1] == "sameAs") {
				enumVal = paramData[paramIndex+2][enumVal[2]];
			}
			if (index < length-1) {
				index = HandleParameters(values, null, enumVal, index, length, sending, isRequest)
			}
		}
	}
	else if (paramType == "bitflags") {
		var str = paramName + " = ";
		var flagsAdded = false;
		var bitFlagsArray = paramData[paramIndex+2];
		for (i = 0; i < bitFlagsArray.length; ++i) {
			var maskArray = bitFlagsArray[i];
			var mask = parseInt(maskArray[0],0);
			var values = maskArray[1];
			var shift = 0;
			if (mask <= 0) {
				console.log("Invalid mask: " + mask);
				return index;
			}
			var shiftedMask = mask;
			while ((shiftedMask & 1) == 0) {
				shift++;
				shiftedMask = shiftedMask >> 1;
			}
			if (typeof(values) == "string") {
				if (shiftedMask == 1) {
					if (value & mask) {
						if (flagsAdded) {
							str += " | ";
						}
						str += values;
						flagsAdded = true;
					}
				}
				else {
					if (flagsAdded) {
						str += " | ";
					}
					str += values + "=" + ((value & mask) >> shift);
					flagsAdded = true;
				}
			}
			else {
				var shiftedEnum = (value & mask) >> shift;
				var enumVal = values[shiftedEnum];
				if (flagsAdded) {
					str += " | ";
				}
				flagsAdded = true;
				if (enumVal == undefined) {
					str += "<span style='color:Magenta;'>UNKNOWN ("+ shiftedEnum + ")</span>";
				}
				else {
					str += enumVal;
				}
			}
			value &= ~mask;
		}
		if (value != 0) {
			if (flagsAdded) {
				str += " | ";
			}
			flagsAdded = true;
			str += "<span style='color:Magenta;'>RESERVED ("+ value + ")</span>";
		}
		if (!flagsAdded) {
			str += "0";
		}
		addHtmlAnnotation(str, firstIndex, index, allowOverlap);
	}
	else if (paramType == "commandclass") {
		var classData = cmdClasses[value];
		if (classData == undefined) {
			addHtmlAnnotation(paramName + " = <span style='color:Magenta;'>Unknown command class: " + value + "</span>", firstIndex, index, allowOverlap);
		} else if (typeof(classData) == "string") {
			addTextAnnotation(paramName + " = " + classData, firstIndex, index, allowOverlap);
		} else {
			addTextAnnotation(paramName + " = " + classData[0], firstIndex, index, allowOverlap);
		}
	}
	else if (paramType == "generictype") {
		var genericData = DeviceTypeTable[value];
		if (genericData == undefined) {
			addHtmlAnnotation(paramName + " = <span style='color:Magenta;'>Unknown generic type: " + value + "</span>", firstIndex, index, allowOverlap);
		} else {
			addTextAnnotation(paramName + " = " + genericData[0], firstIndex, index, allowOverlap);
		}
	}
	else if (paramType == "specifictype") {
		var genericData = DeviceTypeTable[values[index-1]];
		if (genericData == undefined) {
			addHtmlAnnotation(paramName + " = <span style='color:Magenta;'>Unknown specific type: " + value + "</span>", firstIndex, index, allowOverlap);
		} else {
			var specificData = genericData[1][value];
			if (specificData == undefined) {
				addHtmlAnnotation(paramName + " = <span style='color:Magenta;'>Unknown specific type: " + value + " for " + genericData[0] + "</span>", firstIndex, index, allowOverlap);
			}
			else {
				addTextAnnotation(paramName + " = " + specificData, firstIndex, index, allowOverlap);
			}
		}
	}
	else if (paramType == "NonceID") {
		if (value == nonce[0]) {
			addHtmlAnnotation(paramName + " <span style='color:LawnGreen;'>OK</span>", firstIndex, index, allowOverlap);
			packetLength = index + length;
			state = 2;
		}
		else {
			addHtmlAnnotation(paramName + " <span style='color:Red;'>WRONG</span> should be " + byteToHex(nonce[0]), firstIndex, index, allowOverlap);
			return;
		}
	}
	else {
		console.log("Invalid parameter type: " + paramType);
	}
	return index;
}

function ExpandKeys() {
  if (!ZWaveKeys) {
	return false;
  }
  if (ZWaveKeys.expanded) {
	return true;
  }
  var expanded = {};
  var zeroArray = [];
  var macArray = [];
  var encArray = [];
  var keyArray = [];
  for (var i = 0; i < 16; ++i) {
    keyArray[i] = parseInt(ZWaveKeys.M.substring(i*2,i*2+2),16) ^ 0x96;
	zeroArray[i] = 0;
	macArray[i] = 0x55;
	encArray[i] = 0xAA;
  }

  var expandKey = Aes.keyExpansion(keyArray);
  var macKey = Aes.cipher(macArray, expandKey);
  expanded.A = Aes.keyExpansion(macKey);

  var encKey = Aes.cipher(encArray, expandKey);
  expanded.E = Aes.keyExpansion(encKey);

  var expandZero = Aes.keyExpansion(zeroArray);
  var macKey0 = Aes.cipher(macArray, expandZero);
  expanded.A0 = Aes.keyExpansion(macKey0);

  var encKey0 = Aes.cipher(encArray, expandZero);
  expanded.E0 = Aes.keyExpansion(encKey0);

  ZWaveKeys.expanded = expanded;
  return true;
}

function Decrypt(array, index, length, IV, Nonce) {
	DecryptStart = index;
	DecryptLength = length;
	var macData = [0x81, SourceNode, DestinationNode, length].concat(array.slice(index,index+length));

	MACBuffer = IV.concat(Nonce);
	var decBuffer = MACBuffer.slice(0);
	MACBuffer = Aes.cipher(MACBuffer, Key0 ? ZWaveKeys.expanded.A0 : ZWaveKeys.expanded.A);
	for (var i = 0; i < macData.length; ++i) {
		var offset = i % 16;
		MACBuffer[offset] ^= macData[i];
		if (offset == 15 || i == macData.length-1) {
			MACBuffer = Aes.cipher(MACBuffer, Key0 ? ZWaveKeys.expanded.A0 : ZWaveKeys.expanded.A);
		}
	}
	for (var i = 0; i < length; ++i) {
		var offset = i % 16;
		if (offset == 0) {
			decBuffer = Aes.cipher(decBuffer, Key0 ? ZWaveKeys.expanded.E0 : ZWaveKeys.expanded.E);
		}
		array[i+index] ^= decBuffer[offset];
	}
	Key0 = false;
}
]===]
end	 -- GetZSharkJs

function getJSONFuncIDTable()
return [===[
{
	"2": ["FUNC_ID_SERIAL_API_GET_INIT_DATA", ["Version", "BYTE"],
		["Capabilities", "BYTE", "bitflags", [
			[8, "SUC"],
			[4, ["Primary", "Secondary"]],
			[2, "TimerSupport"],
			[1, ["Controller", "Slave"]]
		]],
		["Array length", "BYTE"],
		["Node", "BITARRAY", -1, 1, "node"],
		["Chip Type", "BYTE"],
		["Chip Version", "BYTE"]
	],
	"3": ["FUNC_ID_SERIAL_API_APPL_NODE_INFORMATION", ["NodeInfo", "BYTE", "bitflags", [
			[32, "Listening_Mode_250ms"],
			[16, "Listening_Mode_1000ms"],
			[2, "Optional_Functionality"],
			[1, "Not Listening", "Listening"]
		]],
		["Generic type", "BYTE", "generictype"],
		["Specific type", "BYTE", "specifictype"],
		["Command clast list length", "BYTE"],
		["Supported command class", "ARRAY", -1, "BYTE", "commandclass"]
	],
	"4": "FUNC_ID_APPLICATION_COMMAND_HANDLER",
	"5": ["FUNC_ID_ZW_GET_CONTROLLER_CAPABILITIES", ["Capabilities", "BYTE", "bitflags", [
		[16, "SUC"],
		[8, "RealPrimary"],
		[4, "SIS"],
		[2, "OnOtherNetwork"],
		[1, "Secondary"]
	]]],
	"6": "FUNC_ID_SERIAL_API_SET_TIMEOUTS",
	"7": "FUNC_ID_SERIAL_API_GET_CAPABILITIES",
	"8": "FUNC_ID_SERIAL_API_SOFT_RESET",
	"16": ["FUNC_ID_ZW_SET_RF_RECEIVE_MODE", {
		"Request": [
			["Mode", "BYTE", "enum", {
				"0": "Power Down",
				"1": "Normal"
			}]
		],
		"Response": [
			["RetVal", "BYTE", "enum", {
				"0": "Failure",
				"1": "Success"
			}]
		]
	}],
	"17": "FUNC_ID_ZW_SET_SLEEP_MODE",
	"18": "FUNC_ID_ZW_SEND_NODE_INFORMATION",
	"19": "FUNC_ID_ZW_SEND_DATA",
	"20": "FUNC_ID_ZW_SEND_DATA_MULTI",
	"21": ["FUNC_ID_ZW_GET_VERSION", {
		"Response": [
			["Version", "STRING", "Z"],
			["Level", "BYTE"]
		]
	}],
	"22": "FUNC_ID_ZW_SEND_DATA_ABORT",
	"23": ["FUNC_ID_ZW_RF_POWER_LEVEL_SET", [
		"Power Level", "BYTE", "enum", {
			"0": "normalPower",
			"1": "minus1dBm",
			"2": "minus2dBm",
			"3": "minus3dBm",
			"4": "minus4dBm",
			"5": "minus5dBm",
			"6": "minus6dBm",
			"7": "minus7dBm",
			"8": "minus8dBm",
			"9": "minus9dBm"
		}
	]],
	"24": "FUNC_ID_ZW_SEND_DATA_META",
	"25": "FUNC_ID_ZW_SEND_DATA_GENERIC",
	"27": "FUNC_ID_SET_ROUTING_INFO",
	"28": ["FUNC_ID_ZW_GET_RANDOM", {
		"Request": [
			["Number of random bytes requested", "BYTE"]
		],
		"Response": [
			["Random bytes", "BYTE", "enum", {
				"0": "not available",
				"1": ["available", ["Number of random bytes", "BYTE"],
					["Random Bytes", "ARRAY", -1, "BYTE", "hex"]
				]
			}]
		]
	}],
	"29": "FUNC_ID_ZW_RANDOM",
	"30": "FUNC_ID_ZW_RF_POWER_LEVEL_REDISCOVERY_SET",
	"32": ["FUNC_ID_MEMORY_GET_ID", ["Home ID", "DWORD", "hex"],
		["Primary Controller", "BYTE", "node"]
	],
	"33": ["FUNC_ID_MEMORY_GET_BYTE", {
		"Request": [
			["Offset", "WORD"]
		],
		"Response": [
			["RetVal", "BYTE"]
		]
	}],
	"34": ["FUNC_ID_MEMORY_PUTT_BYTE", {
		"Request": [
			["Offset", "WORD"]
		],
		"Response": [
			["Success", "BYTE"]
		]
	}],
	"35": ["FUNC_ID_MEMORY_GET_BUFFER", {
		"Request": [
			["Offset", "WORD"],
			["Length", "BYTE"]
		],
		"Response": [
			["BUFFER", "ARRAY", 0]
		]
	}],
	"36": ["FUNC_ID_MEMORY_PUT_BUFFER", {
		"Send_Request": [
			["Offset", "WORD"],
			["Length", "WORD"],
			["Buffer", "ARRAY", 0]
		],
		"Response": [
			["RetVal", "BYTE"]
		],
		"Receive_Request": [
			["Callback", "BYTE"]
		]
	}],
	"39": "FUNC_ID_ZW_FLASH_AUTO_PROG_SET",
	"40": "FUNC_ID_NVR_GET_VALUE",
	"41": "FUNC_ID_NVM_GET_ID",
	"42": "FUNC_ID_NVM_EXT_READ_LONG_BUFFER",
	"43": "FUNC_ID_NVM_EXT_WRITE_LONG_BUFFER",
	"44": "FUNC_ID_NVM_EXT_READ_LONG_BYTE",
	"45": "FUNC_ID_NVM_EXT_WRITE_LONG_BYTE",
	"48": "FUNC_ID_CLOCK_SET",
	"49": "FUNC_ID_CLOCK_GET",
	"50": "FUNC_ID_CLOCK_COMPARE",
	"51": "FUNC_ID_RTC_TIMER_CREATE",
	"52": "FUNC_ID_RTC_TIMER_READ",
	"53": "FUNC_ID_RTC_TIMER_DELETE",
	"54": "FUNC_ID_RTC_TIMER_CALL",
	"55": "FUNC_ID_ZW_CLEAR_TX_TIMERS",
	"56": "FUNC_ID_ZW_GET_TX_TIMER",
	"64": "FUNC_ID_ZW_SET_LEARN_NODE_STATE",
	"65": ["FUNC_ID_ZW_GET_NODE_PROTOCOL_INFO", {
		"Request": [
			["Node ID", "BYTE", "node"]
		],
		"Response": [
			["Capability", "BYTE", "bitflags", [
				[128, "Listening"],
				[64, "Routing"],
				[56, ["Reserved", "9600 Baud", "40000 Baud"]],
				[7, ["Reserved",
					"Z-Wave Version 2.0",
					"Z-Wave Version 3.0",
					"Z-Wave Version 4.0"
				]]
			]],
			["Security", "BYTE", "bitflags", [
				[128, "Optional Fuctionality"],
				[64, "Sensor 1000ms"],
				[32, "Sensor 250ms"],
				[16, "Beaming capability"],
				[8, "Routing slave"],
				[4, "Specific device"],
				[2, "Controller"],
				[1, "Security"]
			]],
			["Reserved", "BYTE"],
			["Basic type", "BYTE", "enum", {
				"1": "Controller",
				"2": "Static controller",
				"3": "Slave",
				"4": "Routing slave"
			}],
			["Generic type", "BYTE", "generictype"],
			["Specific type", "BYTE", "specifictype"]
		]
	}],
	"66": "FUNC_ID_ZW_SET_DEFAULT",
	"67": "FUNC_ID_ZW_NEW_CONTROLLER",
	"68": "FUNC_ID_ZW_REPLICATION_COMMAND_COMPLETE",
	"69": "FUNC_ID_ZW_REPLICATION_SEND_DATA",
	"70": ["FUNC_ID_ZW_ASSIGN_RETURN_ROUTE", {
		"Send_Request": [
			["Source Node ID", "BYTE", "node"],
			["Destination Node ID", "BYTE", "node"],
			["Callback ID", "BYTE"]
		],
		"Response": [
			["RetVal", "BYTE", "enum", {
				"0": "Operation_Already_Active",
				"1": "Operation_Started"
			}]
		],
		"Receive_Request": [
			["Callback ID", "BYTE"],
			["Status", "BYTE", "enum", {
				"0": "TRANSMIT_COMPLETE_OK",
				"1": "TRANSMIT_COMPLETE_NO_ACK",
				"2": "TRANSMIT_COMPLETE_FAIL",
				"3": "TRANSMIT_ROUTING_NOT_IDLE",
				"4": "TRANSMIT_COMPLETE_NOROUTE"
			}]
		]
	}],
	"71": ["FUNC_ID_ZW_DELETE_RETURN_ROUTE", {
		"Send_Request": [
			["Node ID", "BYTE", "node"],
			["Callback ID", "BYTE"]
		],
		"Response": [
			["RetVal", "BYTE", "enum", {
				"0": "Operation_Already_Active",
				"1": "Operation_Started"
			}]
		],
		"Receive_Request": [
			["Callback ID", "BYTE"],
			["Result", "BYTE", "enum", {
				"0": "TRANSMIT_COMPLETE_OK",
				"1": "TRANSMIT_COMPLETE_NO_ACK",
				"2": "TRANSMIT_COMPLETE_FAIL",
				"3": "TRANSMIT_ROUTING_NOT_IDLE"
			}]
		]
	}],
	"72": "FUNC_ID_ZW_REQUEST_NODE_NEIGHBOR_UPDATE",
	"73": ["FUNC_ID_ZW_APPLICATION_UPDATE", ["Update state", "BYTE", "enum", {
			"16": "SUC ID",
			"32": "Delete done",
			"64": "New ID assigned",
			"128": "Routing pending",
			"129": "Node info request failed",
			"130": "Node Info request done",
			"132": "Node Info received"
		}],
		["Node ID", "BYTE", "node"],
		["Node info length", "BYTE"],
		["Basic type", "BYTE", "enum", {
			"1": "Controller",
			"2": "Static controller",
			"3": "Slave",
			"4": "Routing slave"
		}],
		["Generic type", "BYTE", "generictype"],
		["Specific type", "BYTE", "specifictype"],
		["Can receive command class", "ARRAY", "M", 239, "BYTE", "commandclass"],
		["Marker", "BYTE", "Optional", "ignore"],
		["Can send command class", "ARRAY", 0, "BYTE", "commandclass"]
	],
	"74": ["FUNC_ID_ZW_ADD_NODE_TO_NETWORK", {
		"Send_Request": [
			["Mode", "BYTE", "bitflags", [
				[128, "Full power"],
				[64, "XXX"],
				[7, ["reserved",
					"ADD_NODE_ANY",
					"ADD_NODE_CONTROLLER",
					"ADD_NODE_SLAVE",
					"ADD_NODE_EXISTING",
					"ADD_NODE_STOP",
					"ADD_NODE_STOP_FAILED"
				]]
			]],
			["Callback ID", "BYTE"]
		],
		"Receive_Request": [
			["Callback ID", "BYTE"],
			["Result", "BYTE", "enum", {
				"1": ["ADD_NODE_STATUS_LEARN_READY", ["Reserved", "WORD", "reserved"]],
				"2": ["ADD_NODE_STATUS_NODE_FOUND", "sameAs", 1],
				"3": ["ADD_NODE_STATUS_ADDING_SLAVE", ["Node ID", "BYTE", "node"],
					["Length", "BYTE"],
					["Basic type", "BYTE", "enum", {
						"1": "Controller",
						"2": "Static controller",
						"3": "Slave",
						"4": "Routing slave"
					}],
					["Generic type", "BYTE", "generictype"],
					["Specific type", "BYTE", "specifictype"],
					["Can receive command class", "ARRAY", "M", 239, "BYTE", "commandclass"],
					["Marker", "BYTE", "Optional", "ignore"],
					["Can send command class", "ARRAY", 0, "BYTE", "commandclass"]
				],
				"4": ["ADD_NODE_STATUS_ADDING_CONTROLLER", "sameAs", 3],
				"5": ["ADD_NODE_STATUS_PROTOCOL_DONE", ["Last node found", "BYTE", "node"],
					["Reserved", "BYTE", "reserved"]
				],
				"6": ["ADD_NODE_STATUS_DONE", "sameAs", 5],
				"7": ["ADD_NODE_STATUS_FAILED", "sameAs", 1]
			}]
		]
	}],
	"75": "FUNC_ID_ZW_REMOVE_NODE_FROM_NETWORK",
	"76": "FUNC_ID_ZW_CREATE_NEW_PRIMARY_CTRL",
	"77": "FUNC_ID_ZW_CONTROLLER_CHANGE",
	"80": "FUNC_ID_ZW_SET_LEARN_MODE",
	"81": "FUNC_ID_ZW_ASSIGN_SUC_RETURN_ROUTE",
	"82": ["FUNC_ID_ZW_ENABLE_SUC", {
		"Request": [
			["SUC/SIS", "BYTE", "enum", {
				"0": "SUC",
				"1": "SIS"
			}],
			["SUC_FUNC", "BYTE", "enum", {
				"0": "Basic SUC",
				"1": "NodeID Server"
			}]
		],
		"Response": [
			["SUC node ID", "BYTE", "node"]
		]
	}],
	"83": "FUNC_ID_ZW_REQUEST_NETWORK_UPDATE",
	"84": "FUNC_ID_ZW_SET_SUC_NODE_ID",
	"85": "FUNC_ID_ZW_DELETE_SUC_RETURN_ROUTE",
	"86": ["FUNC_ID_ZW_GET_SUC_NODE_ID", ["Static Update Controller", "BYTE", "node"]],
	"87": "FUNC_ID_ZW_SEND_SUC_ID",
	"89": "FUNC_ID_ZW_REDISCOVERY_NEEDED",
	"90": "FUNC_ID_ZW_REQUEST_NODE_NEIGHBOR_UPDATE_OPTIONS",
	"92": "FUNC_ID_ZW_REQUEST_NEW_ROUTE_DESTINATIONS",
	"93": "FUNC_ID_ZW_IS_NODE_WITHIN_DIRECT_RANGE",
	"94": "FUNC_ID_ZW_EXPLORE_REQUEST_INCLUSION",
	"96": ["FUNC_ID_ZW_REQUEST_NODE_INFO", {
		"Request": [
			["Node", "BYTE", "node"]
		],
		"Response": [
			["Result", "BYTE", "enum", {
				"0": "Failure",
				"1": "Success"
			}]
		]
	}],
	"97": "FUNC_ID_ZW_REMOVE_FAILED_NODE",
	"98": "FUNC_ID_ZW_IS_FAILED_NODE",
	"99": "FUNC_ID_ZW_REPLACE_FAILED_NODE",
	"112": "FUNC_ID_TIMER_START",
	"113": "FUNC_ID_TIMER_RESTART",
	"114": "FUNC_ID_TIMER_CANCEL",
	"115": "FUNC_ID_TIMER_CALL",
	"120": "FUNC_ID_FIRMWARE_UPDATE",
	"128": ["FUNC_ID_GET_ROUTING_INFO", {
		"Request": [
			["Node", "BYTE", "node"],
			["RemoveBad", "BYTE"],
			["RemoveNonReps", "BYTE"],
			["funcID", "BYTE"]
		],
		"Response": [
			["Neigbors", "BITARRAY", 29, 1, "node"]
		]
	}],
	"129": "FUNC_ID_GET_TX_COUNTER",
	"130": "FUNC_ID_RESET_TX_COUNTER",
	"131": "FUNC_ID_STORE_NODE_INFO",
	"132": "FUNC_ID_STORE_HOME_ID",
	"144": "FUNC_ID_LOCK_ROUTE",
	"145": "FUNC_ID_ZW_SEND_DATA_ROUTE_DEMO",
	"146": "FUNC_ID_GET_LAST_WORKING_ROUTE",
	"147": "FUNC_ID_SET_LAST_WORKING_ROUTE",
	"149": "FUNC_ID_SERIAL_API_TEST",
	"160": "FUNC_ID_SERIAL_API_SLAVE_NODE_INFO",
	"161": "FUNC_ID_APPLICATION_SLAVE_COMMAND_HANDLER",
	"162": "FUNC_ID_ZW_SEND_SLAVE_NODE_INFO",
	"163": "FUNC_ID_ZW_SEND_SLAVE_DATA",
	"164": "FUNC_ID_ZW_SET_SLAVE_LEARN_MODE",
	"165": "FUNC_ID_ZW_GET_VIRTUAL_NODES",
	"166": "FUNC_ID_ZW_IS_VIRTUAL_NODE",
	"167": "FUNC_ID_ZW_GET_VIRTUAL_NODES",
	"168": "FUNC_ID_ZW_APPLICATION_COMMAND_HANDLER_BRIDGE",
	"169": "FUNC_ID_ZW_SEND_DATA_BRIDGE",
	"171": "FUNC_ID_ZW_SEND_DATA_MULTI_BRIDGE",
	"180": "FUNC_ID_ZW_SET_WUT_TIMEOUT",
	"182": "FUNC_ID_ZW_WATCHDOG_ENABLE",
	"183": "FUNC_ID_ZW_WATCHDOG_DISABLE",
	"184": "FUNC_ID_ZW_WATCHDOG_KICK",
	"185": "FUNC_ID_ZW_SET_EXT_INT_LEVEL",
	"186": "FUNC_ID_ZW_RF_POWER_LEVEL_GET",
	"187": "FUNC_ID_ZW_GET_NEIGHBOR_COUNT",
	"188": "FUNC_ID_ZW_ARE_NODES_NEIGHBOURS",
	"189": "FUNC_ID_ZW_TYPE_LIBRARY",
	"190": "FUNC_ID_ZW_SEND_TEST_FRAME",
	"191": "FUNC_ID_ZW_GET_PROTOCOL_STATUS",
	"208": "FUNC_ID_ZW_SET_PROMISCUOUS_MODE",
	"209": "FUNC_ID_PROMISCUOUS_APPLICATION_COMMAND_HANDLER",
	"212": "FUNC_ID_SET_ROUTING_MAX"
}
]===]
end	 -- getJSONFuncIDTable

function getJSONCmdClasses()
return [===[
{
  "0": "COMMAND_CLASS_NO_OPERATION",
  "1": "COMMAND_CLASS_ZWAVE_COMMAND_CLASS",
  "2": "COMMAND_CLASS_ZENSOR_NET",
  "32": [ "COMMAND_CLASS_BASIC", {
    "1": [ "BASIC_SET",
      [ "Value", "BYTE", "enum", {
	      "0": "BASIC_OFF",
		"255": "BASIC_ON",
		 "-1": "Other"
	  }]
    ],
    "2": "BASIC_GET",
    "3": [ "BASIC_REPORT", "sameAs", 1]
  }],
  "33": [ "COMMAND_CLASS_CONTROLLER_REPLICATION", {
    "49": [ "CTRL_REPLICATION_TRANSFER_GROUP",
      [ "Sequence Number", "BYTE" ],
      [ "Group ID", "BYTE"],
      [ "Node ID", "BYTE", "node"]
    ],
    "50": [ "CTRL_REPLICATION_TRANSFER_GROUP_NAME",
      [ "Sequence Number", "BYTE" ],
	  [ "Group ID", "BYTE" ],
      [ "Group Name", "STRING", 0 ]
    ],
    "51": [ "CTRL_REPLICATION_TRANSFER_SCENE",
	  [ "Sequence Number", "BYTE" ],
	  [ "Scene ID", "BYTE" ],
	  [ "Node ID", "BYTE", "node" ],
	  [ "Level", "BYTE" ]
	],
    "52": [ "CTRL_REPLICATION_TRANSFER_SCENE_NAME",
	  [ "Sequence Number", "BYTE" ],
	  [ "Scene ID", "BYTE" ],
	  [ "Scene Name", "STRING", 0 ]
    ]
  }],
  "34": [ "COMMAND_CLASS_APPLICATION_STATUS", {
    "1": [ "APPLICATION_STATUS_BUSY",
      [ "Status", "BYTE", "enum", {
        "0": "Try again later",
        "1": "Try again in Wait Time seconds",
        "2": "Request queued, executed later"
	  }],
	  [ "Time in Seconds", "BYTE" ]
	],
    "2": [ "APPLICATION_REJECTED_REQUEST",
	  [ "Status", "BYTE" ]
    ]
  }],
  "35": "COMMAND_CLASS_ZIP",
  "36": "COMMAND_CLASS_SECURITY_PANEL_MODE",
  "37": [ "COMMAND_CLASS_SWITCH_BINARY", {
    "1": [ "SWITCH_BINARY_SET",
	  [ "Value", "BYTE", "enum", {
           "0": "OFF",
	     "255": "ON"
	  }]
    ],
    "2": "SWITCH_BINARY_GET",
    "3": [ "SWITCH_BINARY_REPORT", "sameAs", 1 ]
  }],
  "38": [ "COMMAND_CLASS_SWITCH_MULTILEVEL", {
    "1": [ "SWITCH_MULTILEVEL_SET",
	  [ "Value", "BYTE" ],
	  [ "DimmingDureation", "BYTE", "Optional" ]
	],
    "2": "SWITCH_MULTILEVEL_GET",
    "3": [ "SWITCH_MULTILEVEL_REPORT",
	  [ "Value", "BYTE" ]
	],
    "4": [ "SWITCH_MULTILEVEL_START_LEVEL_CHANGE",
	  [ "Level", "BYTE", "bitflags", [
	    [128, "RollOver"],
		[ 64, ["Down", "Up"]],
		[ 32, "Ignore StartLevel"]
	  ]],
	  [ "startLevel", "BYTE", "Optional" ]
    ],
    "5": "SWITCH_MULTILEVEL_STOP_LEVEL_CHANGE",
    "6": [ "SWITCH_MULTILEVEL_DO_LEVEL_CHANGE" ,
	  [ "Value", "BYTE", "enum", {
	       "0": "Disable",
		 "255": "Enable"
	  }]
	]
  }],
  "39": [ "COMMAND_CLASS_SWITCH_ALL",	{
    "1": [ "SWITCH_ALL_SET",
      ["State", "BYTE", "bitflags", [
	    [1, ["Exclude_All_Off", "Include_All_off"]],
		[2, ["Exclude_All_On", "Include_All_On"]]
	  ]]
	],
    "2": "SWITCH_ALL_GET",
    "3": [ "SWITCH_ALL_REPORT", "sameAs", 1 ],
    "4": "SWITCH_ALL_ON",
    "5": "SWITCH_ALL_OFF"
  }],
  "40": [ "COMMAND_CLASS_SWITCH_TOGGLE_BINARY", {
    "1": "SWITCH_TOGGLE_BINARY_SET",
	"2": "SWITCH_TOGGLE_BINARY_GET",
	"3": [ "SWITCH_TOGGLE_BINARY_REPORT", "sameAs", 37, 1]
  }],
  "41": [ "COMMAND_CLASS_SWITCH_TOGGLE_MULTILEVEL", {
    "1": "SWITCH_TOGGLE_MULTILEVEL_SET",
    "2": "SWITCH_TOGGLE_MULTILEVEL_GET",
	"3": [ "SWITCH_TOGGLE_MULTILEVEL_REPORT", "sameAs", 37, 1],
    "4": [ "SWITCH_TOGGLE_MULTILEVEL_START_LEVEL_CHANGE", "sameAs", 38, 4 ],
    "5": "SWITCH_TOGGLE_MULTILEVEL_STOP_LEVEL_CHANGE"
  }],
  "42": "COMMAND_CLASS_CHIMNEY_FAN",
  "43": [ "COMMAND_CLASS_SCENE_ACTIVATION", {
	"1": [ "SCENE_ACTIVATION_SET",
		[ "Scene ID", "BYTE" ],
		[ "Dimming Duration", "BYTE" ]
	]
  }],
  "44": [ "COMMAND_CLASS_SCENE_ACTUATOR_CONF", {
	"1": [ "SCENE_ACTUATOR_CONF_SET",
		[ "Scene ID", "BYTE" ],
		[ "Dimming Duration", "BYTE" ],
		[ "Level2", "BYTE", "bitflags", [
			["0x80", "Override"]
		]],
		[ "Level", "BYTE" ]
	],
	"2": [ "SCENE_ACTUATOR_CONF_GET",
		[ "Scene ID", "BYTE" ]
	],
	"3": ["SCENE_ACTUATOR_CONF_REPORT",
		[ "Scene ID", "BYTE" ],
		[ "Level", "BYTE" ],
		[ "Dimming Duration", "BYTE" ]
	]
  }],
  "45": [ "COMMAND_CLASS_SCENE_CONTROLLER_CONF", {
	"1": [ "SCENE_CONTROLLER_CONF_SET",
		[ "Group ID", "BYTE" ],
		[ "Scene ID", "BYTE" ],
		[ "Dimming Duration", "BYTE" ]
	],
	"2": "SCENE_CONTROLLER_CONF_GET",
	"3": ["SCENECONTROLLER_CONF_REPORT", "sameAs", 1]
  }],
  "46": "COMMAND_CLASS_SECURITY_PANEL_ZONE",
  "47": "COMMAND_CLASS_SECURITY_PANEL_ZONE_SENSOR",
  "48": [ "COMMAND_CLASS_SENSOR_BINARY", {
    "2": "SENSOR_BINARY_GET",
    "3": [ "SENSOR_BINARY_REPORT",
      [ "sensorValue", "BYTE", "enum", {
	        "0": "Idle",
	      "255": "Event"
	  }]
	]
  }],
  "49": [ "COMMAND_CLASS_SENSOR_MULTILEVEL", {
    "4": "SENSOR_MULTILEVEL_GET",
    "5": [ "SENSOR_MULTILEVEL_REPORT",
	  [ "Sensor Type", "BYTE", "enum", {
        "1": "Temperature",
        "2": "General purpose value",
        "3": "Luminance",
		"4": "Power",
		"5": "Relative Humidity",
		"6": "Velocity",
		"7": "Direction",
		"8": "Atmospheric Pressure",
		"9": "Barometric Pressure",
		"10": "Solar Radiation",
		"11": "Dew Point",
		"12": "Rain Rate",
		"13": "Tide Level",
		"14": "Weight",
		"15": "Voltage",
		"16": "Current",
		"17": "CO2 Level",
		"18": "Air Flow",
		"19": "Tank Capacity",
		"20": "Distance"
	  }],
	  [ "Level", "BYTE", "bitflags", [
	    ["0x07", "Size"],
		["0x18", "Scale"],
		["0xE0", "Precision"]
	  ]],
	  [ "sensorValue", "BYTE1234" ]
    ]
  }],
  "50": "COMMAND_CLASS_METER",
  "51": "COMMAND_CLASS_COLOR_CONTROL",
  "52": "COMMAND_CLASS_NETWORK_MANAGEMENT_INCLUSION",
  "53": [ "COMMAND_CLASS_METER_PULSE", {
    "4": "METER_PULSE_GET",
    "5": [ "METER_PULSE_REPORT",
	  [ "Pulse Count", "DWORD" ]
	]
  }],
  "54": "COMMAND_CLASS_BASIC_TARIFF_INFO",
  "55": "COMMAND_CLASS_HRV_STATUS",
  "56": "COMMAND_CLASS_THERMOSTAT_HEATING",
  "57": "COMMAND_CLASS_HRV_CONTROL",
  "58": "COMMAND_CLASS_DCP_CONFIG",
  "59": "COMMAND_CLASS_DCP_MONITOR",
  "60": "COMMAND_CLASS_METER_TBL_CONFIG",
  "61": "COMMAND_CLASS_METER_TBL_MONITOR",
  "62": "COMMAND_CLASS_METER_TBL_PUSH",
  "63": "COMMAND_CLASS_PREPAYMENT",
  "64": [ "COMMAND_CLASS_THERMOSTAT_MODE", {
    "1": [ "THERMOSTAT_MODE_SET",
	  [ "Mode", "BYTE", "bitflags", [
		["0x1F", ["Off", "Heat", "Cool", "Auto", "Auxiliary\/Emergency heat", "Resume", "Fan Only", "Furnace", "Dry Air", "Moist Air", "Auto Changeover", "Energy Save Heat", "Energy Save Cool", "Away"]]
	  ]]
    ],
    "2": "THERMOSTAT_MODE_GET",
	"3": [ "THERMOSTAT_MODE_REPORT", "sameAs", 1],
    "4": "THERMOSTAT_MODE_SUPPORTED_GET",
	"5": [ "THERMOSTAT_MODE_SUPPORTED_REPORT",
      [ "Bitmask", "BYTE1234", "bitflags", [
        ["0x0001", "Off"],
		["0x0002", "Heat"],
		["0x0004", "Cool"],
		["0x0008", "Auto"],
		["0x0010", "Auxiliary\/Emergency heat"],
		["0x0020", "Resume"],
		["0x0040", "Fan Only"],
		["0x0080", "Furnace"],
		["0x0100", "Dry Air"],
		["0x0200", "Moist Air"],
		["0x0400", "Auto Changeover"],
		["0x0800", "Energy Save Heat"],
		["0x1000", "Energy Save Cool"],
		["0x2000", "Away"]
      ]]
	]
  }],
  "65": "COMMAND_CLASS_PREPAYMENT_ENCAPSULATION",
  "66": [ "COMMAND_CLASS_THERMOSTAT_OPERATING_STATE", {
	"2": "THERMOSTAT_OPERATING_STATE_GET",
	"3": [ "THERMOSTAT_OPERATING_STATE_REPORT",
	  [ "Operating State", "BYTE", "bitflags", [
	    ["0x0F", {
	      "0": "Idle",
	      "1": "Heating",
		  "2": "Cooling",
		  "3": "Fan only",
		  "4": "Pending heat",
		  "5": "Pending cool",
		  "6": "Vent / Economizer"
	    }]
	  ]]
    ]
  }],
  "67": [ "COMMAND_CLASS_THERMOSTAT_SETPOINT", {
    "1": [ "THERMOSTAT_SETPOINT_SET",
	  [ "SetPoint", "BYTE", "bitflags", [
		["0x0F", {
	      "0": "Not Supported",
	      "1": "Heating 1",
		  "2": "Cooling 1",
		  "7": "Furnace",
		  "8": "Dry Air",
		  "9": "Moist Air",
		  "10": "Auto Changeover",
		  "11": "Energy Save Heat",
		  "12": "Energy Save Cool",
		  "13": "Away Heating"
		}]
	  ]],
	  [ "Level2", "BYTE", "bitflags", [
		["0x07", "Size"],
		["0x18", ["Celsius", "Fahrenheit" ]],
		["0xE0", "Precision"]
	  ]],
	  [ "Value", "BYTE1234" ]
	],
	"2": [ "THERMOSTAT_SETPOINT_GET",
	  [ "SetPoint", "sameAs", 1, 1]
	],
    "3": [ "THERMOSTAT_SETPOINT_REPORT", "sameAs", 1],
    "4": "THERMOSTAT_SETPOINT_SUPPORTED_GET",
    "5": [ "THERMOSTAT_SETPOINT_SUPPORTED_REPORT", "sameAs", 64, 5 ]
  }],
  "68": [ "COMMAND_CLASS_THERMOSTAT_FAN_MODE", {
    "1": [ "THERMOSTAT_FAN_MODE_SET",
	  [ "Mode", "BYTE", "bitflags", [
		["0x05", ["Auto", "On", "?2", "?3", "Cycle"]],
	    ["0x02", ["Low", "High"]]
	  ]]
    ],
    "2": "THERMOSTAT_FAN_MODE_GET",
	"3": [ "THERMOSTAT_FAN_MODE_REPORT", "sameAs", 1],
    "4": "THERMOSTAT_FAN_MODE_SUPPORTED_GET",
	"5": [ "THERMOSTAT_FAN_MODE_SUPPORTED_REPORT",
      [ "Bitmask", "BYTE1234", "bitflags", [
        [1, "AUto Low"],
		[2, "Auto High"],
		[4, "On Low"],
		[8, "On High"]
      ]]
	]
  }],
  "69": [ "COMMAND_CLASS_THERMOSTAT_FAN_STATE",	{
	"2": "THERMOSTAT_FAN_STATE_GET",
	"3": [ "THERMOSTAT_FAN_STATE_REPORT",
	  [ "Operating State", "BYTE", "bitflags", [
	    ["0x0F", {
	      "0": "Fan Off",
	      "1": "Fan On"
	    }]
	  ]]
    ]
  }],
  "70": [ "COMMAND_CLASS_CLIMATE_CONTROL_SCHEDULE", {
    "1": [ "SCHEDULE_SET",
	  [ "Weekday", "BYTE", "bitflags", [
        [7, ["Unused", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" ]]
	  ]],
      [ "Switchpoint", "ARRAY", 9, "WORD3" ]
    ],
    "2": [ "SCHEDULE_GET",
	  [ "Weekday",  "sameAs", 1, 1 ]
	],
	"3": [ "SCHEDULE_REPORT", "sameAs", 1 ],
    "4": "SCHEDULE_CHANGED_GET",
	"5": [ "SCHEDULE_CHANGE_REPORT",
	  [ "change counter", "BYTE" ]
	],
    "6": [ "SCHEDULE_OVERRIDE_SET",
	  [ "OverrideType", "BYTE", "bitflags", [
	    [3, ["No Override", "Temporary Override", "Permanent Override" ]]
	  ]]
	],
	"7": "SCHEDULE_OVERRIDE_GET",
	"8": [ "SCHEDULE_OVERRIDE_REPORT", "sameAs", 6 ]
  }],
  "71": "COMMAND_CLASS_THERMOSTAT_SETBACK",
  "72": "COMMAND_CLASS_RATE_TBL_CONFIG",
  "73": "COMMAND_CLASS_RATE_TBL_MONITOR",
  "74": "COMMAND_CLASS_TARIFF_CONFIG",
  "75": "COMMAND_CLASS_TARIFF_TBL_MONITOR",
  "76": "COMMAND_CLASS_DOOR_LOCK_LOGGING",
  "77": "COMMAND_CLASS_NETWORK_MANANGEMENT_BASIC",
  "78": "COMMAND_CLASS_SCHEDULE_ENTRY_LOCK",
  "80": [ "COMMAND_CLASS_BASIC_WINDOW_COVERING", {
    "1": [ "BASIC_WINDOW_COVERING_START_LEVEL_CHANGE",
	  [ "Level", "BYTE", "bitflags", [
		[64, ["Close", "Open" ]]
	  ]]
	],
    "2": "BASIC_WINDOW_COVERING_STOP_LEVEL_CHANGE"
  }],
  "81": "COMMAND_CLASS_MTP_WINDOW_COVERING",
  "82":	"COMMAND_CLASS_NETWORK_MANAGEMENT_PROXY",
  "83": "COMMAND_CLASS_SCHEDULE",
  "84": "COMMAND_CLASS_NETWORK_MANAGEMENT_PRIMARY",
  "85": "COMMAND_CLASS_TRANSPORT_SERVICE",
  "86": "COMMAND_CLASS_CRC16_ENCAP",
  "87": "COMMAND_CLASS_APPLICATION_CAPABILITY",
  "88": "COMMAND_CLASS_ZIP_ND",
  "89": "COMMAND_CLASS_ASSOCIATION_GRP_INFO",
  "90": "COMMAND_CLASS_DEVICE_RESET_LOCALLY",
  "91": "COMMAND_CLASS_CENTRAL_SCENE",
  "92": "COMMAND_CLASS_IP_ASSOCIATION",
  "93": "COMMAND_CLASS_ANTITHEFT",
  "94": "COMMAND_CLASS_ZWAVEPLUS_INFO",
  "95": "COMMAND_CLASS_ZIP_GATEWAY",
  "96": [ "COMMAND_CLASS_MULTI_INSTANCE", {
    "4": [ "MULTI_INSTANCE_GET",
	  [ "CommandClass", "BYTE", "commandclass" ]
	],
    "5": [ "MULTI_INSTANCE_REPORT",
	  [ "CommandClass", "BYTE", "commandclass" ],
	  [ "Properties1", "BYTE", "bitfalgs", {
	    "0x7F": "instace"
	  }]
	],
    "6": [ "MULTI_INSTANCE_CMD_ENCAP",
	  [ "Properties1", "BYTE", "bitflags", {
	    "0x7F": "instance"
	  }],
	  [ "EncapFrame", "ENCAP" ]
	]
  }],
  "97": "COMMAND_CLASS_ZIP_PORTAL",
  "98": [ "COMMAND_CLASS_DOOR_LOCK", {
    "1": [ "OPERATION_SET",
	  [ "Door lock mode", "BYTE", "enum", {
	    "0": "Unsecured",
		"1": "Unsecured with timeout",
		"16": "Unsecured for inside door handles",
		"17": "Unsecured for inside door handles with timeout",
		"32": "Unsecured for outside door handles",
		"33": "Unsecured for outside door handles with timeout",
		"255": "Secured"
	  }]
	],
    "2": "OPERATION_GET",
	"3": ["OPERATION_REPORT",
	  [ "Door lock mode", "sameAs", 1, 1 ],
	  [	"Properties1", "BYTE", "bitflags", [
	    ["0x0F", "Inside door handles mode"],
		["0xF0", "Outside door handles mode"]
	  ]],
	  [ "Door condition", "BYTE"],
	  [ "Lock timeout (minutes}", "BYTE"],
	  [ "Lock timeout (seconds)", "BYTE"]
	],
    "4": [ "CONFIGURATION_SET",
	  [ "Operation Type", "BYTE", "enum", {
	    "1": "Constant Operation",
		"2": "Timed Operation"
	  }],
	  [	"Properties1", "BYTE", "bitflags", [
	    ["0x0F", "Inside door handles state"],
		["0xF0", "Outside door handles state"]
	  ]],
	  [ "Lock timeout (minutes}", "BYTE"],
	  [ "Lock timeout (seconds)", "BYTE"]
	],
    "5": "CONFIGURATION_GET",
	"6": ["CONFIGURATION_REPORT", "sameAs", 4]
  }],
  "99": [ "COMMAND_CLASS_USER_CODE", {
    "1": [ "USER_CODE_SET",
	  [ "User Identifier", "BYTE" ],
	  [ "User Id Status", "BYTE", "enum", {
	    "0": "Available - Not set",
		"1": "Occupied",
		"2": "Reserved by administrator",
		"255": "Not available"
	  }],
	  [ "User code", "STRING", 0]
	],
	"2": [ "USER_CODE_GET",
	  [ "User identifier", "BYTE" ]
	],
	"3": [ "USER_CODE_REPORT", "sameAs", 1],
	"4": "USERS_NUMBER_GET",
	"5": [ "USERS_NUMBER_REPORT",
	  [ "Supported users", "BYTE" ]
	]
  }],
  "100": "COMMAND_CLASS_APPLIANCE",
  "101": "COMMAND_CLASS_DMX",
  "102": [ "COMMAND_CLASS_BARRIER_OPERATOR", {
    "1": [ "BARRIER_OPERATOR_SET",
      [ "Value", "BYTE", "enum", {
	      "0": "CLOSE",
	    "252": "CLOSING",
		"253": "UNKNOWN",
		"254": "OPENING",
		"255": "OPEN",
		 "-1": "Other"
	  }]
    ],
    "2": "BARRIER_OPERATOR_GET",
    "3": [ "BARRIER_OPERATOR_REPORT", "sameAs", 1]
  }],
  "112": [ "COMMAND_CLASS_CONFIGURATION", {
    "4": [ "CONFIGURATION_SET",
      [ "Parameter Number", "BYTE" ],
	  [ "Level", "BYTE", "bitflags", [
		["0x07", "Size"],
		["0x80", "Default"]
	  ]],
	  [ "Configuration Value", "BYTE1234" ]
	],
    "5": [ "CONFIGURATION_GET",
      [ "Parameter Number", "BYTE" ]
	],
    "6": [ "CONFIGURATION_REPORT",
      [ "Parameter Number", "BYTE" ],
	  [ "Level", "BYTE", "bitflags", [
		["0x07", "Size"]
	  ]],
	  [ "Configuration Value", "BYTE1234" ]
	]
  }],
  "113": [ "COMMAND_CLASS_ALARM", {
    "4": [ "ALARM_GET",
	  [ "Alarm Type", "BYTE", "enum", {
	    "0": "Unused",
		"1": "Smoke",
		"2": "CO",
		"3": "CO2",
		"4": "Heat",
		"5": "Water",
		"6": "Access Control",
		"7": "Burglar",
		"8": "Power Management",
		"9": "System",
		"10": "Emergency",
		"11": "Clock",
		"255": "First"
	  }]
	],
    "5": [ "ALARM_REPORT",
	  [ "Alarm Type", "sameAs", 4, 1 ],
	  [ "Alarm Level", "BYTE", "enum", {
	    "0": "Unused",
		"1": "Intrusion detected 1",
		"2": "Intrusion detected 2",
		"3": "Tampering detected: product cover removed",
		"4": "Tampering detected: incorrect code",
		"7": "Motion detected 7",
		"8": "Motion detected 8",
		"64": "Device initialization process",
		"65": "Door operation force exceeded",
		"66": "Motorexceeded operational time limit",
		"67": "Exceeded physical mechanical limits",
		"68": "Unable to perform requested operation",
		"69": "Remote operation disabled",
		"70": "Device malfunction",
		"71": "Vacation mode",
		"72": "Safety beam",
		"73": "Door sensor not detected",
		"74": "Door sensor low battery",
		"75": "Detected a short in wall station wires",
		"76": "Associated with non-Z-Wave remote control"
	  }],
	  [ "Extra", "Optional", "BYTE"],
	  [ "Extra2", "Optional", "BYTE"],
	  [ "Notification Type", "Optional", "sameAs", 4, 1],
	  [ "Event", "Optional", "sameAs", 5, 2],
	  [ "Event Parameters", "ARRAY", 0, "BYTE" ]
	],
	"6": [ "ALARM_SET",
	  [ "Alarm Type", "sameAs", 4, 1 ],
	  [ "Alarm Status", "BYTE" ]
	],
	"7": "ALARM_TYPE_SUPPORTED_GET",
	"8": [ "ALARM_TYPE_SUPPORTED_REPORT",
	  [ "Alarm report length", "BYTE" ],
	  [ "Alarm supported types 1", "BYTE", "bitflags", [
	    ["0x01", "Smoke"],
	    ["0x02", "CO"],
		["0x04", "CO2"],
		["0x08", "Heat"],
		["0x10", "Water"],
		["0x20", "Access Control"],
		["0x40", "Burglar"],
		["0x80", "Power Management"]
	  ]],
	  [ "Alarm supported types 2", "BYTE", "Optional", "bitflags", [
	    ["0x01", "System"],
	    ["0x02", "Emergency"],
		["0x04", "Clock"]
	  ]]
	]
  }],
  "114": [ "COMMAND_CLASS_MANUFACTURER_SPECIFIC", {
    "4": "MANUFACTURER_SPECIFIC_GET",
    "5": [ "MANUFACTURER_SPECIFIC_REPORT",
	  [ "Manufacturer Id", "WORD", "enum", {
		"0":	"Sigma Designs",
		"1":	"ACT - Advanced Control Technologies",
		"2":	"Danfoss",
		"3":	"Wrap",
		"4":	"Exhausto",
		"5":	"Intermatic",
		"6":	"Intel",
		"7":	"Vimar CRS",
		"8":	"Wayne Dalton",
		"9":	"Sylvania",
		"10":	"Techniku",
		"11":	"CasaWorks",
		"12":	"HomeSeer Technologies",
		"13":	"Home Automated Living",
		"15":	"ConvergeX Ltd.",
		"16":	"Residential Control Systems, Inc. (RCS)",
		"17":	"iCOM Technology b.v.",
		"18":	"Tell It Online",
		"19":	"Internet Dom",
		"20":	"Cyberhouse",
		"22":	"PowerLynx",
		"23":	"HiTech Automation",
		"24":	"Balboa Instruments",
		"25":	"ControlThink LC",
		"26":	"Cooper Wiring Devices",
		"27":	"ELK Products, Inc.",
		"28":	"IntelliCon",
		"29":	"Leviton",
		"30":	"Express Controls (former Ryherd Ventures)",
		"31":	"Scientia Technologies, Inc.",
		"32":	"Universal Electronics Inc.",
		"33":	"Zykronix",
		"34":	"A-1 Components",
		"35":	"Boca Devices",
		"37":	"Loudwater Technologies, LLC",
		"38":	"BuLogics",
		"40":	"2B Electronics",
		"41":	"Asia Heading",
		"42":	"3e Technologies",
		"43":	"Atech",
		"44":	"BeSafer",
		"45":	"Broadband Energy Networks Inc.",
		"46":	"Carrier",
		"47":	"Color Kinetics Incorporated",
		"48":	"Cytech Technology Pre Ltd.",
		"49":	"Destiny Networks",
		"50":	"Digital 5, Inc.",
		"51":	"Electronic Solutions",
		"52":	"El-Gev Electronics LTD",
		"53":	"Embedit A/S",
		"54":	"Exceptional Innovations",
		"55":	"Foard Systems",
		"56":	"Home Director",
		"57":	"Honeywell",
		"58":	"Inlon Srl",
		"59":	"IR Sec. & Safety",
		"60":	"Lifestyle Networks",
		"61":	"Marmitek BV",
		"62":	"Martec Access Products",
		"63":	"Motorola",
		"64":	"Novar Electrical Devices and Systems (EDS)",
		"65":	"OpenPeak Inc.",
		"66":	"Pragmatic Consulting Inc.",
		"67":	"Senmatic A/S",
		"68":	"Sequoia Technology LTD",
		"69":	"Sine Wireless",
		"70":	"Smart Products, Inc.",
		"71":	"Somfy",
		"72":	"Telsey",
		"73":	"Twisthink",
		"74":	"Visualize",
		"75":	"Watt Stopper",
		"76":	"Woodward Labs",
		"77":	"Xanboo",
		"78":	"Zdata, LLC.",
		"79":	"Z-Wave Technologia",
		"80":	"Homepro",
		"81":	"Lagotek Corporation",
		"85":	"Tridium",
		"89":	"Horstmann Controls Limited",
		"91":	"Home Automated Inc.",
		"93":	"Pulse Technologies (Aspalis)",
		"94":	"ViewSonic Corporation",
		"96":	"Everspring",
		"99":	"Jasco Products",
		"100":	"Reitz-Group.de",
		"101":	"RS Scene Automation",
		"102":	"TrickleStar",
		"103":	"CyberTAN Technology, Inc.",
		"104":	"Good Way Technology Co., Ltd",
		"105":	"Seluxit",
		"107":	"Tricklestar Ltd. (former Empower Controls Ltd.)",
		"108":	"Ingersoll Rand (Schlage)",
		"112":	"Homemanageables, Inc.",
		"113":	"LS Control",
		"119":	"INNOVUS",
		"121":	"Cooper Lighting",
		"122":	"Merten",
		"126":	"Monster Cable",
		"127":	"Logitech",
		"128":	"Vero Duco",
		"131":	"MTC Maintronic Germany",
		"132":	"FortrezZ LLC",
		"133":	"Fakro",
		"134":	"AEON Labs",
		"135":	"Eka Systems",
		"137":	"Team Precision PCL",
		"138":	"BeNext",
		"139":	"Trane Corporation",
		"142":	"Raritan",
		"143":	"MB Turn Key Design",
		"145":	"Kamstrup A/S",
		"147":	"San Shih Electrical Enterprise Co., Ltd.",
		"148":	"Alarm.com",
		"149":	"Qees",
		"150":	"NorthQ",
		"151":	"Wintop",
		"152":	"Radio Thermostat Company of America (RTC)",
		"153":	"GreenWave Reality Inc.",
		"154":	"Home Automation Europe",
		"155":	"2gig Technologies Inc.",
		"156":	"Cameo Communications Inc.",
		"157":	"Coventive Technologies Inc.",
		"159":	"Exigent Sensors",
		"258":	"SMK Manufacturing Inc.",
		"259":	"Diehl AKO",
		"265":	"Vision Security",
		"266":	"VDA",
		"268":	"There Corporation",
		"270":	"Poly-control",
		"271":	"Fibargroup",
		"272":	"Frostdale",
		"273":	"Airline Mechanical Co., Ltd.",
		"274":	"MITSUMI",
		"275":	"Evolve",
		"277":	"Z-Wave.Me",
		"278":	"Chromagic Technologies Corporation",
		"279":	"Abilia",
		"280":	"TKB Home",
		"281":	"Omnima Limited",
		"282":	"Wenzhou MTLC Electric Appliances Co.,Ltd.",
		"283":	"Connected Object",
		"284":	"TKH Group / Eminent",
		"285":	"Foxconn",
		"286":	"Secure Wireless",
		"287":	"Ingersoll Rand (Former Ecolink)",
		"288":	"Zonoff",
		"289":	"Napco Security Technologies, Inc.",
		"291":	"IWATSU",
		"300":	"SANAV",
		"301":	"Cornucopia Corp",
		"301":	"Wilshine Holding Co., Ltd",
		"302":	"Wuhan NWD Technology Co., Ltd.",
		"304":	"Quby",
		"305":	"Zipato",
		"306":	"DynaQuip Controls",
		"309":	"ZyXEL",
		"310":	"Systech Corporation",
		"311":	"FollowGood Technology Company Ltd.",
		"313":	"Saeco",
		"314":	"Living Style Enterprises, Ltd.",
		"316":	"Philio Technology Corp",
		"318":	"Holtec Electronics BV",
		"319":	"Defacontrols BV",
		"320":	"Computime",
		"321":	"Innoband Technologies, Inc",
		"327":	"R-import Ltd.",
		"328":	"Eurotronics",
		"329":	"wiDom",
		"330":	"Ecolink",
		"331":	"BFT S.p.A.",
		"332":	"OnSite Pro",
		"333":	"Enblink Co. Ltd",
		"334":	"Check-It Solutions Inc.",
		"335":	"Linear Corp",
		"354":	"HomeScenario",
		"21076":	"Remotec Technology Ltd",
		"65535":	"Not defined or un-defined",
	  }],
	  [ "Product Type Id", "WORD", "hex" ],
	  [ "Procuct Id", "WORD", "hex" ]
	]
  }],
  "115": [ "COMMAND_CLASS_POWERLEVEL",  {
    "1": [ "POWERLEVEL_SET",
      [ "Power Level", "BYTE", "enum", [ "Normal Power", "minus 1 dB", "minus 2 dB", "minus 3 dB", "minus 4 dB", "minus 5 dB", "minus 6 dB", "minus 7 dB", "minus 8 dB", "minus 9 dB" ]],
      [ "Timeout", "BYTE" ]
    ],
    "2": "POWERLEVEL_GET",
    "3": [ "POWERLEVEL_REPORT", "sameAs", 1 ],
    "4": [ "POWERLEVEL_TEST_NODE_SET",
      [ "Test nodeID", "BYTE", "node"	],
	  [ "Power Levl", "sameAs", 1, 1],
      [ "Test Frame Count", "WORD" ]
	],
    "5": "POWERLEVEL_TEST_NODE_GET",
    "6": [ "POWERLEVEL_TEST_NODE_REPORT",
      [ "Test nodeID", "BYTE", "node"	],
	  [ "Status of operation", "BYTE" , "enum" , ["Failed", "Success", "In progress"]],
      [ "Test Frame Count", "WORD" ]
	]
  }],
  "117": [ "COMMAND_CLASS_PROTECTION", {
    "1": [ "PROTECTION_SET",
	  [ "Local Protection State", "BYTE",             "enum", ["Unprotected", "Protection by sequence", "No operation possible" ]],
	  [ "RF Protection State",    "BYTE", "Optional", "enum", ["Unprotected", "Protection by sequence", "No operation possible" ]]
	],
    "2": "PROTECTION_GET",
	"3": [ "PROTECTION_REPORT", "sameAs", 1 ],
	"4": "PROTECTION_SUPPORTED_GET",
	"5": [ "PROTECTION_SUPPORTED_REPORT",
	  [ "level", "BYTE" ],
	  [ "localProtectionState", "WORD" ],
	  [ "rfProtectionState", "WORD" ]
	],
	"6": [ "PROTECTION_EC_SET",
	  [ "nodeId", "BYTE", "node" ]
	],
	"7": "PROTECTION_EC_GET",
	"8": [ "PROTECTION_EC_REPORT", "sameAs", 6],
	"9": [ "PROTECTION_TIMEOUT_SET",
	  [ "timeout", "BYTE" ]
	],
	"10": "PROTECTION_TIMEOUT_GET",
	"11": [ "PROTECTION_TIMEOUT_REPORT", "sameAs", 9]
  }],
  "118": [ "COMMAND_CLASS_LOCK", {
    "1": [ "LOCK_SET", "BYTE", "enum", [ "Unlocked", "Locaked" ]],
	"2": "LOCK_GET",
	"3": [ "LOCK_REPORT", "sameAs", 1 ]
  }],
  "119": "COMMAND_CLASS_NODE_NAMING",
  "122": "COMMAND_CLASS_FIRMWARE_UPDATE_MD",
  "123": "COMMAND_CLASS_GROUPING_NAME",
  "124": "COMMAND_CLASS_REMOTE_ASSOCIATION_ACTIVATE",
  "125": "COMMAND_CLASS_REMOTE_ASSOCIATION",
  "128": [ "COMMAND_CLASS_BATTERY", {
    "2": "BATTERY_GET",
	"3": [ "BATTERY_REPORT",
	  [ "Battery Level", "BYTE" ]
	]
  }],
  "129": [ "COMMAND_CLASS_CLOCK", {
    "4": [ "CLOCK_SET",
	  [ "Level", "BYTE", "bitflags", [
	    ["0xE0", ["Weekday not used", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" ]],
	    ["0x1F", "Hour"]
	  ]],
	  [ "Minute", "BYTE" ]
	],
    "5": "CLOCK_GET",
    "6": [ "CLOCK_REPORT", "sameAs", 4 ]
  }],
  "130": [ "COMMAND_CLASS_HAIL", {
	"1": "HAIL"
  }],
  "132": [ "COMMAND_CLASS_WAKE_UP", {
    "4": [ "WAKE_UP_INTERVAL_SET",
	  ["Seconds", "WORD3" ],
	  ["nodeid", "BYTE", "node" ]
	],
    "5": "WAKE_UP_INTERVAL_GET",
    "6": [ "WAKE_UP_INTERVAL_REPORT",	"sameAs", 4 ],
    "7": "WAKE_UP_NOTIFICATION",
    "8": "WAKE_UP_NO_MORE_INFORMATION",
	"9": "WAKE_UP_INTERVAL_CAPABILITIES_GET",
	"10": ["WAKE_UP_INTERVAL_CAPABILITIES_REPORT",
	  [	"Minimum WakeUp Interval (Seconds)", "WORD3" ],
	  [ "Maximum WakeUp Interval (Seconds)", "WORD3" ],
	  [ "Default WakeUp Interval (Seconds)", "WORD3" ],
	  [ "wakeUp Interval Step (Seconds)", "WORD3" ]
	]
  }],
  "133": [ "COMMAND_CLASS_ASSOCIATION", {
    "1": [ "ASSOCIATION_SET",
      [ "Grouping identifier", "BYTE" ],
	  [ "Nod ID(s)" , "ARRAY", 0, "BYTE", "node"]
	],
    "2": [ "ASSOCIATION_GET",
      [ "Grouping identifier", "BYTE" ]
	],
    "3": [ "ASSOCIATION_REPORT",
      [ "Grouping identifier", "BYTE" ],
      [ "Max Nodes Supported", "BYTE" ],
      [ "Reports To Follow", "BYTE" ],
	  [ "Nod ID(s)" , "ARRAY", 0, "BYTE", "node"]
	],
    "4": [ "ASSOCIATION_REMOVE", "sameAs", 1 ],
    "5": "ASSOCIATION_GROUPINGS_GET",
    "6": [ "ASSOCIATION_GROUPINGS_REPORT",
	  [ "Supported Groupings", "BYTE" ]
	],
	"11": "ASSOCIATION_SPECIFIC_GROUP_GET",
	"12": [ "ASSOCIATION_SPECIFIC_GROUP_REPORT",
      [ "Group", "BYTE" ]
	]
  }],
  "134": [ "COMMAND_CLASS_VERSION", {
    "17": "VERSION_GET",
    "18": [ "VERSION_REPORT",
	  [ "Z-Wave Library Type", "BYTE", "enum", {
	      "1": "CONTROLLER_STATIC",
	      "2": "CONTROLLER",
		  "3": "SLAVE_ENHANCED",
		  "4": "SLAVE",
		  "5": "INSTALLER",
		  "6": "SLAVE_ROUTING",
		  "7": "CONTROLLER_BRIDGE",
		  "8": "DUT"
	  }],
	  [ "Z-Wave Protocol Version", "BYTE" ],
	  [ "Z-Wave Protocol Sub-Version", "BYTE" ],
	  [ "Application Version", "BYTE" ],
	  [ "Application Sub-Version", "BYTE" ]
	],
    "19": [ "VERSION_COMMAND_CLASS_GET",
	  [ "Requested Command Class", "BYTE", "commandclass" ]
	],
    "20": [ "VERSION_COMMAND_CLASS_REPORT",
	  [ "Requested Command Class", "BYTE", "commandclass" ],
	  [ "Command CLass Version", "BYTE" ]
	]
  }],
  "135": [ "COMMAND_CLASS_INDICATOR", {
    "1": [ "INDICATOR_SET",
	  [ "Value", "BYTE" ]
	],
	"2": "INDICATOR_GET",
	"3": [ "INDICATOR_REPORT", "sameAs", 1]
  }],
  "136": [ "COMMAND_CLASS_PROPRIETARY", {
    "1": [ "PROPRIETARY_SET",
	  [ "Data", "ARRAY", 0, "BYTE" ]
	],
	"2": [ "PROPRIETARY_GET", "sameAs", 1],
	"3": [ "PROPRIETARY_REPORT", "sameAs", 1]
  }],
  "137": [ "COMMAND_CLASS_LANGUAGE", {
    "1": [ "LANGUAGE_SET",
	  [ "Language", "STRING", 3 ],
	  [ "Country", "STRING", 2 ]
	],
	"2": "LANGUAGE_GET",
	"3": [ "LANGUAGE_REPORT", "sameAs", 1 ]
  }],
  "138": "COMMAND_CLASS_TIME",
  "139": "COMMAND_CLASS_TIME_PARAMETERS",
  "140": "COMMAND_CLASS_GEOGRAPHIC_LOCATION",
  "141": "COMMAND_CLASS_COMPOSITE",
  "142": "COMMAND_CLASS_MULTI_INSTANCE_ASSOCIATION",
  "143": [ "COMMAND_CLASS_MULTI_CMD", {
    "1": [ "MULTI_CMD_ENCAP",
	  ["Number of commands", "BYTE" ],
	  ["Commands", "ARRAY", -1, "LEN_ENCAP" ]
	]
  }],
  "144": [ "COMMAND_CLASS_ENERGY_PRODUCTION", {
    "2": [ "ENERGY_PRODUCTION_GET",
	  [ "Parameter Number", "BYTE", "enum", [ "Instant energy production", "Total energy production", "Energy production today", "Total production time" ]]
	],
    "3": [ "ENERGY_PRODUCTION_REPORT",
	  [ "Parameter Number", "sameAs", 2, 1 ],
	  [ "level", "BYTE", "bitflags", [
	    ["0x07", "Size"],
		["0x18", "Scale"],
		["0xE0", "Precision"]
	  ]],
	  [ "Value", "BYTE1234" ]
	]
  }],
  "145": [ "COMMAND_CLASS_MANUFACTURER_PROPRIETARY", {
	"*": "Proprietary data"
  }],
  "146": [ "COMMAND_CLASS_SCREEN_MD", {
	"1": [ "SCREEN_METADATA_GET",
		[ "numberOfReports", "BYTE" ],
		[ "Node ID", "BYTE", "node" ]
	],
	"2": [ "SCREEN_METADATA_REPORT",
		[ "properties", "BYTE", "bitflags", [
			[ "0x80", "More Data" ],
			[ "0x38", {
				"0": "Clear",
				"1": "Scroll Down",
				"2": "Scroll Up",
				"7": "Don't Change content"
			}],
			[ "0x07", {
				"0": "Standard ASCII codes",
				"1": "Extended ASCII codes",
				"2": "Unicode",
				"3": "Player Codes"
			}]
		]],
		[ "Attributes A", "BYTE", "bitflags", [
			["0xE0", ["Standard font", "Highlighted", "Larger font"]],
			["0x10", ["No clear part A", "Clear part A"]],
			["0x0F", ["Button 1", "Button 2", "Button 3", "Button 4", "Button 5"]]
		]],
		[ "Char Position A", "BYTE" ],
		[ "Number of chars A", "BYTE" ],
		[ "Text A", "STRING", -1],
		[ "Attributes B", "BYTE", "Optional", "bitflags", [
			["0xE0", ["Standard font", "Highlighted", "Larger font"]],
			["0x10", ["No clear part B", "Clear part B"]],
			["0x0F", ["Button 1", "Button 2", "Button 3", "Button 4", "Button 5"]]
		]],
		[ "Char Position B", "BYTE" ],
		[ "Number of chars B", "BYTE" ],
		[ "Text B", "STRING", -1]
	]
  }],
  "147": [ "COMMAND_CLASS_SCREEN_ATTRIBUTES", {
  	"1": "SCREEN_ATTRIBUTES_GET",
  	"2": [ "SCREEN_ATTRIBUTES_REPORT",
		[ "properties1", "BYTE", "bitflags", [
			["0x1F", "NumberOfLines" ],
			["0x20", "EscapeSequence"]
		]],
	    [ "numberOfCharactersPerLine", "BYTE" ],
	    [ "sizeOfLineBuffer", "BYTE" ],
	    [ "numericalRepresentation", "BYTE", "bitflags", [
			["0x01", "Supports ASCII codes"],
			["0x02", "Supports ASCII and extended codes"],
			["0x04", "Supports Unicode"],
			["0x08", "Supports ASCII and Player codes"]
	    ]],
	    [ "screenTimeout", "BYTE", "Optional" ]
  	]
  }],
  "148": "COMMAND_CLASS_SIMPLE_AV_CONTROL",
  "149": "COMMAND_CLASS_AV_CONTENT_DIRECTORY_MD",
  "150": "COMMAND_CLASS_AV_RENDERER_STATUS",
  "151": "COMMAND_CLASS_AV_CONTENT_SEARCH_MD",
  "152": [ "COMMAND_CLASS_SECURITY", {
	"2": "SECURITY_COMMANDS_SUPPORTED_GET",
	"3": [ "SECURITY_COMMANDS_SUPPORTED_REPORT",
		["Reports to follow", "BYTE"],
		["Can receive command class", "ARRAY", "M", 239, "BYTE", "commandclass"],
		["Marker", "BYTE", "Optional", "ignore" ],
		["Can send command class", "ARRAY", 0, "BYTE", "commandclass"]
	],
	"4": [ "SECURITY_SCHEME_GET",
	   ["Supported Security Schemes", "BYTE"]
	],
	"5": [ "SECURITY_SCHEME_REPORT", "sameAs", 4, "Key0"],
	"8": [ "SECURITY_SCHEME_INHERIT", "sameAs", 4],
	"6": [ "NETWORK_KEY_SET",
		["Network Key", "ARRAY", 0 ]
	],
	"7": "NETWORK_KEY_VERIFY",
	"64": "SECURITY_NONCE_GET",
	"128": [ "SECURITY_NONCE_REPORT",
		["Nonce", "ARRAY", 8, "NONCE"]
	],
	"129": [ "SECURITY_MESSAGE_ENCAPSULATION",
		["Initialization Vector", "ARRAY", 8, "IV"],
		["Properties1", "BYTE", "bitflags", [
			["0x0F", "Sequence Counter" ],
			["0x10", "Sequenced"],
			["0x20", "Second Frame"]
		]],
		["Encrypted data", "ARRAY", 0, -9, "EENCAP"],
		["Receiver Nonce Identifier", "BYTE", "NonceID"],
		["Message Authentication Code", "ARRAY", 8, "MAC"]
	],
	"193": [ "SECURITY_MESSAGE_ENCAPSULATION_NONCE_GET", "sameAs", 129]
  }],
  "153": "COMMAND_CLASS_AV_TAGGING_MD",
  "154": "COMMAND_CLASS_IP_CONFIGURATION",
  "155": "COMMAND_CLASS_ASSOCIATION_COMMAND_CONFIGURATION",
  "156": "COMMAND_CLASS_SENSOR_ALARM",
  "157": "COMMAND_CLASS_SILENCE_ALARM",
  "158": "COMMAND_CLASS_SENSOR_CONFIGURATION",
  "239": "COMMAND_CLASS_MARK",
  "240": ["COMMAND_CLASS_NON_INTEROPERABLE", {
  }]
}
]===]
end	 -- getJSONCmdClasses

function getJSONDeviceTypeTable()
return [===[
{
	"1": [ "Generic Controller", {
		"0": "Not used",
		"1": "Portable remote controller",
		"2": "Portable scene controller",
		"3": "Portable installer tool"
	}],
	"2": [ "Static controller", {
		"0": "Not used",
		"1": "PC controller",
		"2": "Scene controller",
		"3": "Static installer tool"
	}],
	"3": [ "A/V control point", {
		"0": "Not used",
		"4": "Satellite receiver",
		"17": "Satellite receiver v2",
		"18": "Doorbell"
	}],
	"4": [ "Display", {
		"0": "Not used",
		"1": "Simple display"
	}],
	"8": [ "thermostat", {
		"0": "Not used",
		"1": "Thermostat heating",
		"2": "Thermostat general",
		"3": "Setback schedule thermostat",
		"4": "Setpoint thermostat",
		"5": "Setback thermostat",
		"6": "Thermostat general v2"
	}],
	"9": [ "window covering", {
		"0": "Not used",
		"1": "Simple window covering"
	}],
	"15": [ "repeater slave", {
		"0": "Not used",
		"1": "Repeater slave"
	}],
	"16": [ "switch binary", {
		"0": "Not used",
		"1": "Power switch binary",
		"3": "Scene switch binary"
	}],
	"17": [ "switch multilevel", {
		"0": "Not used",
		"1": "Power switch multilevel",
		"3": "Motor multiposition",
		"4": "Scene switch multilevel",
		"5": "Class A motor contol",
		"6": "Class A motor contol",
		"7": "Class A motor contol"
	}],
	"18": [ "switch remote", {
		"0": "Not used",
		"1": "Switch remote binary",
		"2": "Switch remote multilevel",
		"3": "Switch remote toggle binary",
		"4": "Switch remote toggle multilevel"
	}],
	"19": [ "switch toggle", {
		"0": "Not used",
		"1": "Switch toggle binary",
		"2": "Switch toggle multilevel"
	}],
	"20": [ "zip gateway", {
		"0": "Not used",
		"1": "Zip gateway",
		"2": "Zip Advanced gateway"
	}],
	"21": [ "zip node", {
		"0": "Not used",
		"1": "Sip node",
		"2": "Sip Advanced node"
	}],
	"32": [ "sensor binary", {
		"0": "Not used",
		"1": "Routing sensor binary"
	}],
	"33": [ "sensor multilevel", {
		"0": "Not used",
		"1": "Routing sensor multilevel",
		"2": "Chimney fan"
	}],
	"48": [ "meter pulse", {
		"0": "Not used"
	}],
	"49": [ "meter", {
		"0": "Not used",
		"1": "Simple meter"
	}],
	"64": [ "entry control", {
		"0": "Not used",
		"1": "Door lock",
		"2": "Advanced door lock",
		"3": "Secure keypad door lock",
		"7": "Garage door opener"
	}],
	"80": [ "semi interoperable", {
		"0": "Not used",
		"1": "Energy production"
	}],
	"161": [ "sensor alarm", {
		"0": "Not used",
		"1": "Basic routing alarm sensor",
		"2": "Routing alarm sensor",
		"3": "Basic zensor net alarm sensor",
		"4": "Zensor net alarm sensor",
		"5": "Advanced zensor net alarm sensor",
		"6": "Basic routing smoke sensor",
		"7": "Routing smoke sensor",
		"8": "Basic zensor net smoke sensor",
		"9": "Zensor net smoke sensor",
		"10": "Advanced zensor net smoke sensor"
	}],
	"255": [ "non interoperable", {
		"0": "Not used"
	}]
}
]===]
end -- getJSONDeviceTypeTable

function htmlJavaScript1()
	return '<script type="text/javascript">'
	.. htmkJavaScriptSource()
   	.. "var ZWaveNodeList = " .. getJSONZWaveNodeList()
   	.. "var ZWaveKeys = " .. getJSONZWaveKeys()
   	.. GetAesJs()
   	.. GetZSharkJs()
   	.. "var funcIDTable = " .. getJSONFuncIDTable()
   	.. "var cmdClasses =	" .. getJSONCmdClasses()
   	.. "var DeviceTypeTable = " .. getJSONDeviceTypeTable()
   	.. getInfoViewerJS()
   	.. "</script>"
end

local function htmlJavaScript2()
return [[
<script type="text/javascript">
]]..htmkJavaScriptSource()..[[

var URL_PART_1    = '/port_3480/data_request';
var PLUGIN_URL_ID = 'al_info';

// define JSON.parse for older browsers.
"object"!=typeof JSON&&(JSON={}),function(){"use strict"
function f(t){return 10>t?"0"+t:t}function quote(t){return escapable.lastIndex=0,escapable.test(t)?'"'+t.replace(escapable,function(t){var e=meta[t]
return"string"==typeof e?e:"\\u"+("0000"+t.charCodeAt(0).toString(16)).slice(-4)})+'"':'"'+t+'"'}function str(t,e){var r,n,o,f,u,p=gap,i=e[t]
switch(i&&"object"==typeof i&&"function"==typeof i.toJSON&&(i=i.toJSON(t)),"function"==typeof rep&&(i=rep.call(e,t,i)),typeof i){case"string":return quote(i)
case"number":return isFinite(i)?i+"":"null"
case"boolean":case"null":return i+""
case"object":if(!i)return"null"
if(gap+=indent,u=[],"[object Array]"===Object.prototype.toString.apply(i)){for(f=i.length,r=0;f>r;r+=1)u[r]=str(r,i)||"null"
return o=0===u.length?"[]":gap?"[\n"+gap+u.join(",\n"+gap)+"\n"+p+"]":"["+u.join(",")+"]",gap=p,o}if(rep&&"object"==typeof rep)for(f=rep.length,r=0;f>r;r+=1)"string"==typeof rep[r]&&(n=rep[r],o=str(n,i),o&&u.push(quote(n)+(gap?": ":":")+o))
else for(n in i)Object.prototype.hasOwnProperty.call(i,n)&&(o=str(n,i),o&&u.push(quote(n)+(gap?": ":":")+o))
return o=0===u.length?"{}":gap?"{\n"+gap+u.join(",\n"+gap)+"\n"+p+"}":"{"+u.join(",")+"}",gap=p,o}}"function"!=typeof Date.prototype.toJSON&&(Date.prototype.toJSON=function(){return isFinite(this.valueOf())?this.getUTCFullYear()+"-"+f(this.getUTCMonth()+1)+"-"+f(this.getUTCDate())+"T"+f(this.getUTCHours())+":"+f(this.getUTCMinutes())+":"+f(this.getUTCSeconds())+"Z":null},String.prototype.toJSON=Number.prototype.toJSON=Boolean.prototype.toJSON=function(){return this.valueOf()})
var cx=/[\u0000\u00ad\u0600-\u0604\u070f\u17b4\u17b5\u200c-\u200f\u2028-\u202f\u2060-\u206f\ufeff\ufff0-\uffff]/g,escapable=/[\\\"\x00-\x1f\x7f-\x9f\u00ad\u0600-\u0604\u070f\u17b4\u17b5\u200c-\u200f\u2028-\u202f\u2060-\u206f\ufeff\ufff0-\uffff]/g,gap,indent,meta={"\b":"\\b","	":"\\t","\n":"\\n","\f":"\\f","\r":"\\r",'"':'\\"',"\\":"\\\\"},rep
"function"!=typeof JSON.stringify&&(JSON.stringify=function(t,e,r){var n
if(gap="",indent="","number"==typeof r)for(n=0;r>n;n+=1)indent+=" "
else"string"==typeof r&&(indent=r)
if(rep=e,e&&"function"!=typeof e&&("object"!=typeof e||"number"!=typeof e.length))throw Error("JSON.stringify")
return str("",{"":t})}),"function"!=typeof JSON.parse&&(JSON.parse=function(text,reviver){function walk(t,e){var r,n,o=t[e]
if(o&&"object"==typeof o)for(r in o)Object.prototype.hasOwnProperty.call(o,r)&&(n=walk(o,r),void 0!==n?o[r]=n:delete o[r])
return reviver.call(t,e,o)}var j
if(text+="",cx.lastIndex=0,cx.test(text)&&(text=text.replace(cx,function(t){return"\\u"+("0000"+t.charCodeAt(0).toString(16)).slice(-4)})),/^[\],:{}\s]*$/.test(text.replace(/\\(?:["\\\/bfnrt]|u[0-9a-fA-F]{4})/g,"@").replace(/"[^"\\\n\r]*"|true|false|null|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?/g,"]").replace(/(?:^|:|,)(?:\s*\[)+/g,"")))return j=eval("("+text+")"),"function"==typeof reviver?walk({"":j},""):j
throw new SyntaxError("JSON.parse")})}()


function infoCallBack(jsonObj) {
   if (jsonObj && jsonObj.capabilities) {
      document.getElementById('zwdeviceinfo').innerHTML = jsonObj.capabilities;
      window.scrollTo(0, document.body.scrollHeight);
   }
}

function getZWDeviceInfo (args, callBack)
{
   args.id = 'lr_'+PLUGIN_URL_ID;
   args.random = Math.random();

   ajaxRequest(URL_PART_1, args, function(response) {
       if (response.responseType == "json") {
	       callBack(response.response)
       }
       else {
	       callBack(JSON.parse(response.response));
       }
   });
}

function spanClick(zwnodeid) {
    getZWDeviceInfo({fnc: 'getZWDeviceInfo', zwnodeid: zwnodeid}, infoCallBack);
    return false;
}

function startUp() {
}

// execute this
window.onload = startUp;

</script>]]
end

local function htmlHeader()
return [[<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
<meta http-equiv="content-type" content="text/html; charset=utf-8"/>]]
end

-- The web page that shows the log file to the user
local function htmlLogViewerPage(theApp)
    local title        = APPS[theApp]['title'] or 'App not found'
    local file         = APPS[theApp]['file']  or 'File not found'
    local header       = APPS[theApp]['host'] .. ': ' .. file or ''

    local strTab = {
    htmlHeader(),
    '<title>'..title..'</title>',
    htmlCssStyle1(),
    htmlJavaScript1(),
[==[
    </head>
      <body>
	      <div id="topRibbon">
            <button class="button" type="button" onClick="clearLog()">Clear</button>
]==],
--[==[
            <ul id="sddm">
              <li>
                <a href="#" onmouseover="mopen('m1')" onmouseout="mclosetime()">Home</a>
                <div id="m1" onmouseover="mcancelclosetime()" onmouseout="mclosetime()">
                  <a href="#">HTML/CSS</a>
                  <a href="#">DHTML Menu</a>
                  <a href="#">JavaScript</a>
                </div>
              </li>
              <li>
                <a href="#" onmouseover="mopen('m2')" onmouseout="mclosetime()">Download</a>
                <div id="m2" onmouseover="mcancelclosetime()" onmouseout="mclosetime()">
                  <a href="#">ASP Server-side</a>
                  <a href="#">Pulldown navigation</a>
                  <a href="#">AJAX Drop Submenu</a>
                  <a href="#">DIV Cascading </a>
                </div>
              </li>
			  <li>
			    <span onmouseover="mopen('m3')" onmouseout="mclosetime()">Fruits</span>
                <div id="m3" onmouseover="mcancelclosetime()" onmouseout="mclosetime()">
				  <ul>
			        <li><input type="checkbox" />Apple </li>
            	    <li><input type="checkbox" />Orange</li>
                	<li><input type="checkbox" />Grapes </li>
            	    <li><input type="checkbox" />Berry </li>
            	    <li><input type="checkbox" />Mango </li>
            	    <li><input type="checkbox" />Banana </li>
            	    <li><input type="checkbox" />Tomato</li>
				  </ul>
				</div>
			  </li>
              <li><a href="#">Order</a></li>
              <li><a href="#">Help</a></li>
              <li><a href="#">Contact</a></li>
            </ul>
--]==]
[==[
            <div style="clear:both"></div>

	      </div>
	      <div id="scrollArea">
            <h3>]==]..header..[==[</h3>
            <pre id="log">
		      <div id="bottomDummy"/>
            </pre>
	      </div>
          <div id="bottomRibbon">
	      </div>
      </body>
    </html>
]==]
    }

    return table.concat(strTab,'\n')
end

-- The Ajax routine that returns the log file updates to the web page
-- With help from the Python code by Dr Xi at http://www.xinotes.org/notes/note/155/
function ajaxResult(theApp, startLine)

    -- validate startLine
    startLine = tonumber(startLine)

    if startLine then
        if startLine < 1 then startLine = 1 end
    else
        startLine = 1
    end

    local appInfo = APPS[theApp]
    local host    = appInfo['host']
    local shell   = appInfo['shell']
    local file    = appInfo['file']

    -- all the strings go in a table. It's much more efficient
    -- as the garbage collection is much less frequent
    local lines = {}

    -- start the xml data
    table.insert(lines, '<?xml version="1.0" encoding="utf-8"?>\n')

    -- line 2: this will later be replaced with the actual start line count
    table.insert(lines, '<ajax-response startLine="start line count">\n')

    -- the opening cdata tag is deliberately broken up, so it doesn't get parsed as an opening cdata tag elsewhere
    table.insert(lines, '<!['..'CDATA[')

    -- the opening cdata tag is deliberately broken up, so it doesn't get parsed as an opening cdata tag elsewhere
    local errorStartTag = '<?xml version="1.0" encoding="utf-8"?>\n<ajax-response startLine="1">\n<!['..'CDATA[<span class="error">'..host..' error: '

    -- the cdata closing tag is deliberately broken up, so it doesn't get parsed as a Lua comment terminal somewhere else
    local lastTag = ']'..']>\n</ajax-response>\n'

    if not file or file == '' then return errorStartTag..'No entry for log file name</span>'..lastTag end

    -- messages to the user
    local message = ''

    -- has the pattern been changed?
    if luaPattern ~= latestPattern then

        -- validate the incoming pattern
        local valid, filteredStr = pcall(string.find, 'Hello testing', latestPattern)
        if not valid then
            -- do a search for something useful instead eg level 01 error messages
            message = '<span class="default">****** Lua pattern was invalid - showing level 01 error messages instead ******</span><br/>'
            latestPattern = '^[0][1]'
        else
            if latestPattern == '' then
                message = '<span class="default">****** Lua pattern is now set to: show all ******</span><br/>'
            else
                local patternInfo = '****** Lua pattern is now set to: '..latestPattern..' ******'
                message = '<span class="default">'..escXMLentities(patternInfo)..'</span><br/>'
            end
        end
        table.insert(lines,message)

        luaPattern = latestPattern

        -- force a new search backwards by a max of INITIAL_LINES
        startLine = 1
    end

    -- first time round get the current number of lines in the file as the starting point
    if startLine == 1 then
        debug('FIRST Starting startLine = '..tostring(startLine))

        -- WC word count command - get newline (\n) count
        -- '2>&1' pipes stderr into our file
        local cmd = 'wc -l '..file..' 2>&1'
        if shell ~= '' then cmd = shell..' "'..cmd..'"' end
        debug(cmd)

        -- f1 is of type 'userdata' and will not be nil if the command fails - that's why we also pipe in the stderr stream
        local f1 = io.popen(cmd)

        if not f1 then return errorStartTag..'Failed to open file: '..file..'</span>'..lastTag end

        local lineCountStr1 = f1:read()
        lineCountStr1 = lineCountStr1:lower()
        debug('lineCountStr1 = '..lineCountStr1)

        -- was an error message piped into the file?
        local error = lineCountStr1:find('no such file')

        -- a total hack but we know if the file was found or not
        if error then return errorStartTag..'Failed to open file: '..file..'</span>'..lastTag end

        f1:close()

        local fileLineCount1 = tonumber(lineCountStr1:match('%d+'))

        if not fileLineCount1 then return errorStartTag..'Failed to get a line count of:'..file..'</span>'..lastTag end

        if fileLineCount1 > INITIAL_LINES then startLine = fileLineCount1 - INITIAL_LINES end

        debug('SECOND startLine = '..tostring(startLine))
    end

    --[[
    --WC TAIL word count and tail file command - get newline (\n) count and output the last N lines - example result:
    33055 LuaUPnP.log
    06    01/07/13 18:55:15.662    Device_Variable::m_szValue_set device: 8 service: urn:micasaverde-com:serviceId:SecuritySensor1 variable:  [35;1mTripped [0m was: 0 now: 1 #hooks: 1 upnp: 0 v:0xadb1f8/NONE duplicate:0 <0x2f66c680>
    ...
    07    01/07/13 18:55:17.163    Event::Evaluate 8 z4 is tripped scene Standard lamp: on for 5 mins is false repeat 0/-1 <0x2f66c680>
    50    01/07/13 18:55:17.163       <--note the partial line here
    ]]

    -- note the 'plus' in the tail options: means 'start at' this line
  --local cmd = 'wc -l '..file..' && tail -n +'..startLine..' '..file..' |  sed -e "s/</\\&lt;/g" | /usr/bin/ansi2html'
    -- This version "nides" the useless <0x........> at the end of each log line. It should be in dark grey, but the ansi2html tool makes it black, which is OK too.
    local cmd = 'wc -l '..file..' && tail -n +'..startLine..' '..file.." |  sed -e 's/<0x........>$/'$'\\x1B''[30;1m&'$'\\x1B''[0m/' -e 's/</\\&lt;/g' | /usr/bin/ansi2html"

    if shell ~= '' then cmd = shell..' "'..cmd..'"' end
    debug(cmd)

    -- f2 is of type 'userdata' and will not be nil if the command fails
    local f2 = io.popen(cmd)

    local lineCountStr2 = f2:read()

    local fileLineCount2 = tonumber(lineCountStr2:match('%d+'))

    if not fileLineCount2 then return errorStartTag..'Failed to get a line count of: '..file..'</span>'..lastTag end
    debug('A startLine = '..tostring(startLine))
    debug('B fileLineCount2 = '..tostring(fileLineCount2))

    -- if the log contains no new entries since the last check then startLine will be greater than fileLineCount2 by 1
    local totCount = fileLineCount2 - (startLine - 1)

    -- we need to catch when the OS starts a new log file. We just output a message and update with the new log's
    -- content next time round. Note that f2 this time round will contain just the line count and no log data.
    if totCount < 0 then
        startLine = 1

        message = '<span class="default">****** Log files rotated: log entries for the last few seconds may be missings ******</span><br/>'
        table.insert(lines,message)

    else -- continue as normal
        debug('C startLine = '..tostring(startLine))

        local filter = luaPattern ~= ''

        -- we're not going to rely on  'for line in f2:lines()' to remain working when the logs rotate or disappear
        for i = 1, totCount, 1 do
            local line = f2:read()

            -- protective measure - in theory this should not trigger
            if not line then
                debug('D startLine = '..tostring(startLine))
                debug('E fileLineCount2 = '..tostring(fileLineCount2))
                debug('F totCount = '..tostring(totCount))
                debug('Your theory is wrong - the file read was nil')
                break
            end

            local usefulLine = true
            if filter then
				local textline = line:gsub('<[^>]*>','')
				textline = textline:gsub('&(%l+);', function(escape) debug("found escape "..escape); return htmlEscapes[escape]; end)
                local result = textline:find(luaPattern)
                if not result then usefulLine = false end
            end

            if usefulLine then
                table.insert(lines,line.."<br/>")
            end -- if usefulLine

            startLine = startLine + 1
        end -- for
    end -- if startLine > fileLineCount2

    f2:close()

    -- now the startline count is valid, stick it back up near the top of the table where it belongs
    lines[2] = '<ajax-response startLine="'..startLine..'">\n'

    -- for debug purposes we can insert an extra \n before 'lastTag', so
    -- the output from each ajax call appears separated on the web page
    -- table.insert(lines,'\n'..lastTag)
    table.insert(lines,lastTag)

    -- this is where all the processing time gets saved
    -- as we kept the garbage collection to a minimum
    return table.concat(lines)
end

-- Output the logging page or get the ajax result for the logging page
local function getLog(lcParameters)
    -- get the ajax result for the logging page?
    if lcParameters.app and lcParameters.startline then
        return ajaxResult(lcParameters.app, lcParameters.startline),"text/xml"
    elseif lcParameters.app then  -- run the logging page
        return htmlLogViewerPage(lcParameters.app),"text/html"
    end
end

-- Get the Z-Wave devices
local function getZWDevices()
    local zwDevices = {}
    local zwInt = getZWInterfacelId()

    -- extract the info about the Z-Wave devices
    local maxDescLength = 0
    for k, v in pairs(luup.devices) do
        -- we're only interested in the Z-Wave devices
        if (v.device_num_parent == zwInt) then
            local mInfo = luup.variable_get(ZWD_SID, "ManufacturerInfo", k)
            local cap   = luup.variable_get(ZWD_SID, "Capabilities",     k)
            local vers  = luup.variable_get(ZWD_SID, "VersionInfo",      k)
            local nb    = luup.variable_get(ZWD_SID, "Neighbors",        k)

            -- comms info
            local c1 = luup.variable_get(ZWD_SID, 'PollOk',      k)
            local c2 = luup.variable_get(ZWD_SID, 'PollTxFail',  k)
            local c3 = luup.variable_get(ZWD_SID, 'PollNoReply', k)

            if nb then
                local record = {
                   deviceId = k,
                   zwNodeId = v.id,
                   description = v.description,
                   manufInfo = mInfo,
                   capabilities = cap,
                   neighbors = nb,
				   version = vers,
                   com1 = c1,
                   com2 = c2,
                   com3 = c3,
                   tabLine = ''}

                -- an ordered list that we can later also look up by its Z-Wave node id
                table.insert(zwDevices, record)

                -- get the longest device description so we can format any description columns to suit
                local currentLength = v.description:len()
                if (currentLength > maxDescLength) then maxDescLength = currentLength end
            end
        end
    end

    -- sort by Z-Wave node ID
    table.sort(zwDevices, function (a,b) return tonumber(a.zwNodeId) < tonumber(b.zwNodeId) end)

    -- for each Z-Wave node id, we need to know its position in the neighborhood table
    local reverseLookup = {}
    -- zwNodeId is a string
    for k, v in ipairs(zwDevices) do
        reverseLookup[v.zwNodeId] = k
    end

    -- for debugging only
    if DEBUG_MODE then
        for k, v in ipairs(zwDevices) do
            luup.log('Device ID:    '..tostring(v.deviceId))
            luup.log('Z-Wave ID:    '..v.zwNodeId)     -- this is a string
            luup.log('Description:  '..v.description)  -- this is a string
            luup.log('Manuf_Info:   '..v.manufInfo)    -- this is a string
            luup.log('Capabilities: '..v.capabilities) -- this is a string
            luup.log('Neighbors:    '..v.neighbors)    -- this is a string
        end
        for k, v in pairs(reverseLookup) do
            luup.log(k..' '..tostring(v))
        end
    end

    return zwDevices, reverseLookup, maxDescLength
end

-- Output the Z-Wave Interface state variables
local function getZWInterface()
    local zwInt = getZWInterfacelId()

    local zwIntTab = {}

    -- do the the times first
    local t1 = tonumber(luup.variable_get(ZW_SID, 'LastUpdate',       zwInt), 10)
    local t2 = tonumber(luup.variable_get(ZW_SID, 'LastDongleBackup', zwInt), 10)
    local t3 = tonumber(luup.variable_get(ZW_SID, 'LastHeal',         zwInt), 10)
    local t4 = tonumber(luup.variable_get(ZW_SID, 'LastRouteFailure', zwInt), 10)

    local dt1 = ''
    local dt2 = ''
    local dt3 = ''
    local dt4 = ''

    -- nil values are possible
    local dtFormat = ' --> %Y-%m-%d  %X'
    if t1 then dt1 = os.date(dtFormat, t1) else t1 = '' end
    if t2 then dt2 = os.date(dtFormat, t2) else t2 = '' end
    if t3 then dt3 = os.date(dtFormat, t3) else t3 = '' end
    if t4 then dt4 = os.date(dtFormat, t4) else t4 = '' end

    -- we need to assign these to a variable before actually utilising them
    -- doing this results in errors when the result is nil:
    -- table.insert(zwIntTab, 'Use45 '..tostring(luup.variable_get(ZW_SID, 'Use45',zwInt)))

    local vg1  = luup.variable_get(ZW_SID, 'Use45',             zwInt)
    local vg2  = luup.variable_get(ZW_SID, 'UseMR',             zwInt)
    local vg3  = luup.variable_get(ZW_SID, 'LimitNeighbors',    zwInt)
    -- t1..dt1
    local vg4  = luup.variable_get(HD_SID, 'AutoConfigure',     zwInt)
    local vg5  = luup.variable_get(ZW_SID, 'NetStatusID',       zwInt)
    local vg6  = luup.variable_get(ZW_SID, 'NetStatusText',     zwInt)
    local vg7  = luup.variable_get(ZW_SID, 'LockComPort',       zwInt)
    local vg8  = luup.variable_get(ZW_SID, 'ComPort',           zwInt)
    local vg9  = luup.variable_get(ZW_SID, 'PollingEnabled',    zwInt)
    local vg10 = luup.variable_get(ZW_SID, 'PollDelayInitial',  zwInt)
    local vg11 = luup.variable_get(ZW_SID, 'PollDelayDeadTime', zwInt)
    local vg12 = luup.variable_get(ZW_SID, 'PollMinDelay',      zwInt)
    local vg13 = luup.variable_get(ZW_SID, 'PollFrequency',     zwInt)
    local vg14 = luup.variable_get(ZW_SID, 'VersionInfo',       zwInt)
    local vg15 = luup.variable_get(ZW_SID, 'HomeID',            zwInt)
    local vg16 = luup.variable_get(ZW_SID, 'Role',              zwInt)
    -- t2..dt2
    local vg17 = luup.variable_get(HD_SID, 'LastTimeOffset',    zwInt)
    local vg18 = luup.variable_get(HD_SID, 'LastUpdate',        zwInt)
    -- t3..dt3
    local vg19 = luup.variable_get(ZW_SID, 'TO3066',            zwInt)
    local vg20 = luup.variable_get(ZW_SID, 'LastError',         zwInt)
    -- t4..dt4
    local vg21 = luup.variable_get(ZW_SID, 'SceneIDs',          zwInt)

    table.insert(zwIntTab, 'Use45             '..tostring(vg1))
    table.insert(zwIntTab, 'UseMR             '..tostring(vg2))
    table.insert(zwIntTab, 'LimitNeighbors    '..tostring(vg3))
    table.insert(zwIntTab, 'LastUpdate        '..t1..dt1)
    table.insert(zwIntTab, 'AutoConfigure     '..tostring(vg4))
    table.insert(zwIntTab, 'NetStatusID       '..tostring(vg5))
    table.insert(zwIntTab, 'NetStatusText     '..tostring(vg6))
    table.insert(zwIntTab, 'LockComPort       '..tostring(vg7))
    table.insert(zwIntTab, 'ComPort           '..tostring(vg8))
    table.insert(zwIntTab, 'PollingEnabled    '..tostring(vg9))
    table.insert(zwIntTab, 'PollDelayInitial  '..tostring(vg10))
    table.insert(zwIntTab, 'PollDelayDeadTime '..tostring(vg11))
    table.insert(zwIntTab, 'PollMinDelay      '..tostring(vg12))
    table.insert(zwIntTab, 'PollFrequency     '..tostring(vg13))
    table.insert(zwIntTab, 'VersionInfo       '..tostring(vg14))
    table.insert(zwIntTab, 'HomeID            '..tostring(vg15))
    table.insert(zwIntTab, 'Role              '..tostring(vg16))
    table.insert(zwIntTab, 'LastDongleBackup  '..t2..dt2)
    table.insert(zwIntTab, 'LastTimeOffset    '..tostring(vg17))
    table.insert(zwIntTab, 'LastUpdate        '..tostring(vg18))
    table.insert(zwIntTab, 'LastHeal          '..t3..dt3)
    table.insert(zwIntTab, 'TO3066            '..tostring(vg19))
    table.insert(zwIntTab, 'LastError         '..tostring(vg20))
    table.insert(zwIntTab, 'LastRouteFailure  '..t4..dt4)
    table.insert(zwIntTab, 'SceneIDs          '..tostring(vg21))

    return table.concat(zwIntTab,'\n')
end

-- Output the Z-Wave neighbours table
local function getZWNeighbours()
    local formatTab = {}
    local headerTab = {}
    local underscoreTab = {}
    for k, v in ipairs(zwDevices) do
        -- make a string format for each line in the neighborhood table
        -- apparently you can have up to 232 nodes so use a field width of 4
        table.insert(formatTab, '%4s')
        table.insert(underscoreTab,'----')

        -- make a neighborhood table header showing all the node ids
        table.insert(headerTab, v.zwNodeId)
    end
    local formatting = table.concat(formatTab)

    local line1A = string.format('%'..(4+maxDescLength+5)..'s', ' ')
    local line1B = string.format(formatting, unpack(headerTab))
    local line1  = line1A..line1B

    local line2Str = table.concat(underscoreTab)
    local line2 = string.format('%'..(4+maxDescLength+5)..'s%s', ' ', line2Str)
    debug(line1)
    debug(line2)

    local nbTable = {line1, line2}

    -- produce the neighborhood table
    for k, v in ipairs(zwDevices) do

        -- make a line template for each Z-Wave device
        local templateTab = {}
        for k2, v2 in ipairs(zwDevices) do
            table.insert(templateTab, '')
        end

        -- split out the neighbors for each Z-Wave device
        for nb in v.neighbors:gmatch('%d+') do
            -- a disconnected Z-Wave device can have no neighbors
            if nb then
                -- debug('Neighbors:'..nb)

                -- for this Z-Wave node id, find its index in the line template
                local idx = reverseLookup[nb]

                -- now mark it in the correct position in the line
                if idx then
                   templateTab[idx] = '@'
                else
                   -- everything talks to the ZW controller which is not in our device list - it's node 1
                   if (nb ~= '1') then debug('This Z-Wave device references a none existent neighbor:'..v.description) end
                end
            else
                debug('This Z-Wave device has a nil neighbor:'..v.description)
            end
        end

        -- concatenate the line table into a formatted string
        local line = string.format(formatting, unpack(templateTab))

        -- add in the first few columns in the neighborhood table
        local lineStart = string.format('%-4s%'..maxDescLength..'s%4s', v.deviceId, v.description, v.zwNodeId)

        debug(lineStart..'|'..line)

        table.insert(nbTable, (lineStart..'|'..line))
    end

    return table.concat(nbTable,'\n')
end

-- Output the Z-Wave Comms Info
local function getZWComms()
    local commsTab = {}

    local line = string.format('%'..(4+maxDescLength)..'s%12s%12s%12s', ' ', 'PollOk', 'PollTxFail', 'PollNoReply')
    table.insert(commsTab, line)

    for k, v in ipairs(zwDevices) do

        local c1 = v.com1  -- PollOk
        local c2 = v.com2  -- PollTxFail
        local c3 = v.com3  -- PollNoReply

        if not c1 then c1 = '----' end
        if not c2 then c2 = '----' end
        if not c3 then c3 = '----' end

        -- use a dummy, as it of a known pattern; unlike the actual description
        -- that could contain magic pattern chararacters like dashes for example
        local dummy = string.rep('d', v.description:len())

        line = string.format('%-4s%-'..maxDescLength..'s%12s%12s%12s', v.deviceId, dummy, c1, c2, c3)

        -- present the formatted descriptions as simulated links
        local replacesDummy = '<span class="scripted-link" onclick=spanClick("'..v.zwNodeId..'")>'..escXMLentities(v.description)..'</span>'
        line = line:gsub(dummy,replacesDummy)

        table.insert(commsTab, line)
    end

    return table.concat(commsTab,'\n')
end

-- Output the info re: the Z-Wave device
local function getZWDeviceInfo(lcParameters)

	if #zwDevices == 0 then
	    -- get the Z-Wave devices info
	    zwDevices, reverseLookup, maxDescLength = getZWDevices()
	end

    -- make sure we have a Z-Wave node ID
    if not lcParameters.zwnodeid then return end
    local zwNodeId = lcParameters.zwnodeid
    debug (zwNodeId)
    -- check that the string represents a number
    if not tonumber(zwNodeId) then return end

    -- get the capabilities; zwNodeId is a string
    local idx = reverseLookup[zwNodeId]
    if not idx then return end

    -- this will be returned as json
    local msg = ''
    local intro = '{"capabilities": "'
    local deviceInfoTab = {zwDevices[idx].description..' --> zw node: '..zwNodeId}

    local capabilities = zwDevices[idx].capabilities
    debug (capabilities)
    if not capabilities or (capabilities == '') then
        msg = deviceInfoTab[1]..'\nCapabilities not known'
        return intro..escJSONentities(msg)..'"}'
    end

    table.insert(deviceInfoTab, 'Capabilities: '..capabilities)

    local version = zwDevices[idx].version
    local v1, v2, v3, v4, v5 = version:match('^(%d+),(%d+),(%d+),(%d+),(%d+)')
	if v5 ~= nil then
    	table.insert(deviceInfoTab, 'Version: '..version)
	end
	table.insert(deviceInfoTab,"");

    -- For bit definitions refer to:  Z-Wavefunction 0x41  FUNC_ID_ZW_GET_NODE_PROTOCOL_INFO
    -- http://code.google.com/p/open-zwave/source/browse/trunk/cpp/src/Node.cpp
    -- http://code.google.com/p/open-zwave/source/browse/trunk/cpp/src/Node.h
    -- FLiRS = Frequently Listening Routing Slave
    --
    -- Byte0                        Byte1
    -- d7 Listens yes/no            d7 Optional command classes
    -- d6 Routes yes/no             d6 Sensor 1000ms Can RX a Beam = FLIRS = !Listens && (b6||b5)
    -- d5 br2 Max Baud rate where:  d5 Sensor 250ms
    -- d4 br1 010 = 40k             d4 Can TX a Beam Yes/No
    -- d3 br0                       d3 Routing Slave Yes/No
    -- d2 ver2 Version where:       d2 Specific device
    -- d1 ver1 000 = Ver 1          d1 Controller Yes/No
    -- d0 ver0                      d0 Security Yes/No

    -- the first two numbers are bytes 0 and 1, in decimal
    local b0, b1, b2, b3, b4, b5 = capabilities:match('^(%d-),(%d-),(%d-),(%d-),(%d-),(%d-),')
    debug('b0 = '..b0..' b1 = '.. b1)

    -- if the strings look like they may represent bytes
    if tonumber(b0) and tonumber(b1) then
        b0 = dec2StrInBase(b0, 2, 8)
        b1 = dec2StrInBase(b1, 2, 8)
        debug(b0)
        debug(b1)

        local formatStr = '%-23s: '
        local result = ''

        local listener = getBit(b0,7)
        if listener then result = 'yes' else result = 'no' end
        table.insert(deviceInfoTab, string.format(formatStr..result, 'Listens'))

        if getBit(b0,6) then result = 'yes' else result = 'no' end
        table.insert(deviceInfoTab, string.format(formatStr..result, 'Routes'))

        local flirs1000 = getBit(b1,6)
        local flirs250  = getBit(b1,5)

        -- it's assumed that if it listens it doesn't have FLirs
        if listener then
            result = 'no'
        -- these are probably mutually exclusive but just in case
        elseif flirs1000 and flirs250 then
            result = 'yes - FLiRS 1000 and FLiRS 250'
        elseif flirs1000 then
            result = 'yes - FLiRS 1000'
        elseif flirs250 then
            result = 'yes - FLiRS 250'
        else -- not a listener and has no Beam receiver
            result = 'no'
        end
        table.insert(deviceInfoTab, string.format(formatStr..result, 'Has a Beam receiver'))

        if getBit(b1,4) then result = 'yes' else result = 'no' end
        table.insert(deviceInfoTab, string.format(formatStr..result, 'Can transmit a Beam'))

        if getBit(b1,3) then result = 'yes' else result = 'no' end
        table.insert(deviceInfoTab, string.format(formatStr..result, 'Routing slave'))

        if getBit(b1,0) then result = 'yes' else result = 'no' end
        table.insert(deviceInfoTab, string.format(formatStr..result, 'Security device'))
    end

    table.insert(deviceInfoTab, string.format("Basic Device Class     : %s", zwBasicTypes[b3]))
    table.insert(deviceInfoTab, string.format("Generic Device Class   : %s", zwDeviceTypes[b4][1]))
    table.insert(deviceInfoTab, string.format("Specific Device Class  : %s", zwDeviceTypes[b4][2][b5]))

	if (v5 ~= nil) then
	    -- crawl down into COMMAND_CLASS_VERSION, VERSION_REPORT, Z-Wave Library Type enum
		local libraryType = zwClasses["134"][2]["18"][2][4][v1]
		if type(libraryType) == "string" then
	    	table.insert(deviceInfoTab, string.format("Z-Wave Library Type    : %s", libraryType))
		else
	    	table.insert(deviceInfoTab, string.format("Z-Wave Library Type    : unknown(%s)", tostring(v1)))
		end
	    table.insert(deviceInfoTab, string.format("Z-Wave Library version : %s.%s", tostring(v2), tostring(v3)))
	    table.insert(deviceInfoTab, string.format("Device firmware version: %s.%s", tostring(v4), tostring(v5)))
	end
	table.insert(deviceInfoTab,"");

    -- find all the Z-Wave classes this device can handle
    local classes = capabilities:match('|(.+)')
    for classVersion in classes:gmatch('[%dS:]+') do  -- note the colon
		local theClass, security, theVersion = classVersion:match("(%d+)(S?):(%d+)")
		if theVersion == nil then
        	theClass, security = classVersion:match('(%d+)(S?)')
		end
		local entry = zwClasses[theClass]
        if not entry then
			entry = "(unknown command class)"
		end
		if type(entry) == "table" then
			entry = entry[1]
		end
		if security == "S" then
			entry = entry .. " (requires security wrapper)"
		end
		if theVersion then
			entry = entry .. " version " .. theVersion
		end
        table.insert(deviceInfoTab, string.format('%-4s ' .. entry, theClass))
    end

    -- this is placed in a pre tag block
    msg = table.concat(deviceInfoTab,'\n')

    return intro..escJSONentities(msg)..'"}',"text/json"
end

-- Output the Z-Wave neighbours info
local function getZWInfo()
	if #zwDevices == 0 then
	    -- get the Z-Wave devices info
	    zwDevices, reverseLookup, maxDescLength = getZWDevices()
	end

    local title   = 'Info Viewer'
    local header1 = 'Z-Wave interface'
    local header2 = 'Z-Wave neighbours'
    local header3 = 'Z-Wave comms'
    local header4 = 'Z-Wave device info'

    local strTab = {
    htmlHeader(),
    '<title>'..title..'</title>',
    htmlCssStyle2(),
    htmlJavaScript2(),
    '</head>\n',
    '<body>',
    '<h3>'..header1..'</h3>',
    '<div>',
    '<pre id="zwinterface">',
    getZWInterface(),
    '</pre>',
    '</div>',
    '<h3>'..header2..'</h3>',
    '<div>',
    '<pre id="zwneighbors">',
    getZWNeighbours(),
    '</pre>',
    '</div>',
    '<h3>'..header3..'</h3>',
    '<div>',
    '<pre id="zwcomms">',
    getZWComms(),
    '</pre>',
    '</div>',
    '<h3>'..header4..'</h3>',
    '<div>',
    'Click on a device link immediately above',
    '<pre id="zwdeviceinfo">',
    '</pre>',
    '</div>',
    '</body>',
    '</html>'
    }
    return table.concat(strTab,'\n'),"text/html"
end

-- get Vera's IP address
local function getIP()
    local title   = 'Vera IP'
    local header1 = 'Vera&#39s IP address'

    local TIME_OUT = 5
    local URL = 'http://checkip.dyndns.org'

    local ipAddress = 'IP address not found!'
    local status, html = luup.inet.wget(URL, TIME_OUT)
    if html then
        local result = html:match('%D(%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?)%D')
        if result then ipAddress = 'IP address is: '..result end
    end

    local strTab = {
    htmlHeader(),
    '<title>'..title..'</title>',
    '</head>\n',
    '<body>',
    '<h3>'..header1..'</h3>',
    '<div>',
    ipAddress,
    '</div>',
    '</body>',
    '</html>'
    }
    return table.concat(strTab,'\n'),"text/html"
end

-- First web page
local function htmlIntroPage()
    local DATA_MINE = '/www/dm/index.html'
    local dm = ''
    if isFilePresent(DATA_MINE) then dm = '<a href="/dm/index.html">dataMine</a><br/>' end

    local title  = 'Info Viewer'
    local header = 'InfoViewer ver: '..PLUGIN_VERSION
    local app = 'localapp'
    local links = '<a href="'..URL_ID..'&amp;fnc=getLog&amp;app='..app..'">'..'View logs: '..APPS[app]['title']..'</a><br/>'

	local luci = '<a href="../cgi-bin/luci.sh">LuCI Router interface</a>><br/>'
	local lucifile = io.open("/www/cgi-bin/luci.sh")
	if lucifile then
		io.close(lucifile)
	else
		luci=''
	end

    local strTab = {
    htmlHeader(),
    '<title>'..title..'</title>',
    '</head>\n',
    '<body>',
    '<h3>'..header..'</h3>',
    '<div>Using: '.._VERSION..'<br/>ZShark requires verbose logging to be on.<br/><br/>Select a link below to view:',
    '<h4>Vera internals</h4>',
    links,
    '<a href="'..URL_ID..'&amp;fnc=getzwinfo">Vera Z-Wave</a><br/>',
	'<a href="../cgi-bin/cmh/get_zwave_jobs.sh">Executed Z-Wave jobs</a><br/>',
    '<a href="'..URL_ID..'&amp;fnc=getip">Vera&#39s IP address</a><br/>',
	luci,
    dm,
    '<a href="./data_request?id=lu_status&amp;output_format=xml">Vera status</a><br/>',
    '<a href="./data_request?id=user_data&amp;output_format=xml">Vera devices</a><br/>',
    '<a href="./data_request?id=lu_invoke">Vera invoke</a><br/>',
	'<a href="../cgi-bin/cmh/NetworkTroubleshoot.sh">Network troubleshooter</a><br/>',
	'<a href="../cgi-bin/cmh/sysinfo.sh">System Information</a><br/>',
    '<h4>Vera logs</h4>',
	'<a href="../cgi-bin/cmh/log.sh?Device=LuaUPnP">Alternate LuaUPnP log</a><br/>',
	'<a href="../cgi-bin/cmh/log.sh?Device=NetworkMonitor">Nwtwork Monitor log</a><br/>',
	'<a href="../cgi-bin/cmh/log.sh?Device=serproxy">Serial Proxy log</a><br/>',
	'<a href="../cgi-bin/cmh/log.sh?Device=syslog">System log</a><br/>',
  --'<a href="../cgi-bin/cmh/log.sh?Device=HTTP server error log">lighttpd_error</a><br/>',
	'<a href="../cgi-bin/cmh/log.sh?Device=upgrade">Upgrade log</a><br/>',
  --'<a href="../cgi-bin/cmh/log.sh?Device=0">DCE Router log</a><br/>',
  --'<a href="../cgi-bin/cmh/log.sh?Device=9">9-ZWave.log</a><br/>',
  --'<a href="../cgi-bin/cmh/log.sh?Device=10">10-Generic_IP_Camera_Manager.log</a><br/>',
    '<h4>Validators</h4>',
    '<a href="http://jsonlint.com/">JSONLint</a><br/>',
    '<a href="http://validator.w3.org/">HTML Validator</a><br/>',
    '<a href="http://www.w3schools.com/xml/xml_validator.asp">XML Validator</a><br/>',
    '<a href="http://www.javascriptlint.com/online_lint.php">JavaScript Lint</a><br/>',
    '<a href="http://jigsaw.w3.org/css-validator/">CSS Validation</a><br/>',
    '<h4>Lua</h4>',
    '<a href="http://lua-users.org/wiki/LuaDirectory">Lua Wiki</a><br/>',
    '<a href="http://www.lua.org/manual/5.1/">Lua 5.1 Manual</a><br/>',
    '<a href="http://code.google.com/p/luaforwindows/">luaforwindows</a><br/>',
    '<a href="http://www.eclipse.org/koneki/ldt/">Lua with Eclipse</a><br/>',
    '<h4>Vera info</h4>',
    '<a href="http://bugs.micasaverde.com/main_page.php">Vera Bug Reporting</a><br/>',
    '<a href="http://code.mios.com">Vera Plugin code repository</a><br/>',
    '<a href="http://wiki.micasaverde.com/index.php/Luup_Lua_extensions">Luup extensions</a><br/>',
    '<a href="http://wiki.micasaverde.com/index.php/Luup_Scenes_Events">Luup Scenes Events</a><br/>',
    '<a href="http://wiki.micasaverde.com/index.php/Luup_Requests">Luup Requests</a><br/>',
    '<a href="http://wiki.micasaverde.com/index.php/Luup_UPnP_Variables_and_Actions">Luup UPnP Variables and Actions</a><br/>',
    '<a href="http://wiki.micasaverde.com/index.php/Luup_plugin_icons">Luup plugin icons</a><br/>',
    '<a href="http://wiki.micasaverde.com/index.php/Luup_plugins:_Static_JSON_file">Luup Static JSON file</a><br/>',
    '<a href="http://wiki.micasaverde.com/index.php/Luup_UPNP_Files">Luup UPNP Files</a><br/>',
    '<a href="http://wiki.micasaverde.com/index.php/JavaScript_API">JavaScript API</a><br/>',
    '<a href="http://www.pepper1.net/zwavedb/">ZWave database of devices</a><br/>',
    '<a href="http://wiki.micasaverde.com/index.php/ZWave_Command_Classes">ZWave Command Classes</a><br/>',
    '<a href="http://wiki.micasaverde.com/index.php/ZWave_Debugging">ZWave Debugging</a><br/>',
    '<a href="http://wiki.micasaverde.com/index.php/MigrateTo452">The infamous Migrate To Z-wave version 452 hack</a><br/>',
    '</div>',
    '</body>',
    '</html>'
    }

    return table.concat(strTab,'\n')
end

-- Entry point for all html page requests and all ajax function calls
-- http://vera_ip_address/port_3480/data_request?id=al_info
function requestMain (lul_request, lul_parameters, lul_outputformat)
    debug('request is: '..tostring(lul_request))
    for k,v in pairs(lul_parameters) do debug ('parameters are: '..tostring(k)..'='..tostring(v)) end
    debug('outputformat is: '..tostring(lul_outputformat))

    if not (lul_request:lower() == PLUGIN_URL_ID) then return end

    -- set the parameters key and value to lower case
    local lcParameters = {}
    for k, v in pairs(lul_parameters) do lcParameters[k:lower()] = v:lower() end

    -- output the intro page?
    if not lcParameters.fnc then return htmlIntroPage() end -- no 'fnc' parameter so do the intro

    if (lcParameters.fnc == 'getlog')          then return getLog(lcParameters) end
    if (lcParameters.fnc == 'getzwinfo')       then return getZWInfo() end
    if (lcParameters.fnc == 'getzwdeviceinfo') then return getZWDeviceInfo(lcParameters) end
    if (lcParameters.fnc == 'getip')           then return getIP() end

    return '{}'
end

--[[
a Vera action
refer to: I_InfoViewer1.xml
http://wiki.micasaverde.com/index.php/Luup_Declarations
function SetParameters (lul_device, lul_settings)
    setParms(lul_settings.newLuaPattern)
end
]]
local function setParms(newLuaPattern)
    -- a blank in the device entry box gives us a nil, not an empty string
    latestPattern = newLuaPattern or ''

    luup.variable_set(PLUGIN_SID, "LuaPattern", latestPattern, THIS_LUL_DEVICE)
end

-- start up the device
-- refer to: I_InfoViewer1.xml
-- <startup>luaStartUp</startup>
function luaStartUp(lul_device)
    THIS_LUL_DEVICE = lul_device

    zwClasses     = JSON.decode(getJSONCmdClasses())
    zwDeviceTypes = JSON.decode(getJSONDeviceTypeTable())

    if (not(zwClasses and zwDeviceTypes)) then
        debug('JSON decode failed. Plugin exiting.',50)
        return false, 'JSON decode failed', THIS_LUL_DEVICE
    end

    -- first time round we need to set up the 'LuaPattern' state variable
    latestPattern = luup.variable_get(PLUGIN_SID, "LuaPattern", THIS_LUL_DEVICE)

    if not latestPattern then -- default to show all log entries
        latestPattern = ''
        luup.variable_set(PLUGIN_SID, "LuaPattern", latestPattern, THIS_LUL_DEVICE)
    end

    -- registers a handler for the functions called via ajax
    luup.register_handler('requestMain', PLUGIN_URL_ID)

    -- on success
    return true, 'All OK', PLUGIN_NAME
end
