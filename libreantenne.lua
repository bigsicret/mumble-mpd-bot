----------------------------------------------------------------------
-- Mumble/IRC/MPD bot with lua
--
-- require "socket"
-- require "mpd"
-- require "os"
----------------------------------------------------------------------


-- Boolean if users need to be registered on the server to trigger sounds
local require_registered = true

-- Boolean if sounds should stop playing when another is triggered
local interrupt_sounds = true

-- Boolean if the bot should move into the user's channel to play the sound
local should_move = false

local disable_jingle_ts = 0

local mpd_client = {loaded = false}


----------------------------------------------------------------------
-- global configuration variables
----------------------------------------------------------------------
local configuration_file="./bot.conf"
local flags = {

   loaded = false,

   debug = "",         -- debug flags -> integer

   mumble_user = "",   -- mumble bot username -> string

   irc_server = "",    -- irc server address -> IP or DNS
   irc_port = "",      -- irc server port -> integer 2**16   
   irc_chan = "",      -- irc chan -> string

   mpd_server = "",    -- mpd server address -> IP or DNS
   mpd_port = "",      -- mpd port -> integer 2**16
   mpd_password = "",  -- mpd password -> string

   mumble_server = "", -- mumble server address -> IP or DNS
   mumble_port = "",   -- mumble port -> integer 2**16
   mumble_chan = "",    -- mumble chan -> string

   web_server = "",    -- mpd web server -> string
   web_port = "",      -- mpd port -> integer 2**16

   jingle_conf = "",   -- jingle configuration file path string
   jingle_path = ""    -- jingle music path -> string
}

-- violet local msg_prefix = "<span style='color:#738'>&#x266B;&nbsp;-&nbsp;"
-- local msg_prefix = "<span style='color:#384'>&#x266B;&nbsp;-&nbsp;"
-- local msg_prefix = "<span style='color:#339933'>&#x266B;&nbsp;-&nbsp;"
local msg_prefix = "<span style='color:#777'>&#x266B;&nbsp;-&nbsp;"
local msg_suffix = "&nbsp;-&nbsp;&#x266B;</span>"

----------------------------------------------------------------------
-- Sound file path prefix
----------------------------------------------------------------------
local jingles_path = "jingles/"
local mpd_connect = mpd_connect


-- module utf8 -- some code from here : https://github.com/alexander-yakushev/awesompd/blob/master/utf8.lua
-- returns the number of bytes used by the UTF-8 character at byte i in s
-- also doubles as a UTF-8 character validator

local utf8 = {}

function utf8.charbytes (s, i)
   -- argument defaults
   i = i or 1
   local c = string.byte(s, i)
   
   -- determine bytes needed for character, based on RFC 3629
   if c > 0 and c <= 127 then
      -- UTF8-1
      return 1
   elseif c >= 194 and c <= 223 then
      -- UTF8-2
      -- local c2 = string.byte(s, i + 1)
      return 2
   elseif c >= 224 and c <= 239 then
      -- UTF8-3
      -- local c2 = s:byte(i + 1)
      -- local c3 = s:byte(i + 2)
      return 3
   elseif c >= 240 and c <= 244 then
      -- UTF8-4
      -- local c2 = s:byte(i + 1)
      -- local c3 = s:byte(i + 2)
      -- local c4 = s:byte(i + 3)
      return 4
   end
end
-- returns the number of characters in a UTF-8 string
function utf8.len (s)
   local pos = 1
   local bytes = string.len(s)
   local len = 0
   
   while pos <= bytes and len ~= chars do
      local c = string.byte(s,pos)
      len = len + 1
      
      pos = pos + utf8.charbytes(s, pos)
   end
   
   if chars ~= nil then
      return pos - 1
   end
   
   return len
end


-- initialize the translation table 
function utf8.init ()
	local unaccent_from, unaccent_to =
   "ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝàáâãäåçèéêëìíîïñòóôõöøùúûüý",
   "AAAAAACEEEEIIIINOOOOOOUUUUYaaaaaaceeeeiiiinoooooouuuuy"

        utf8.unaccent_table = {}
        local i,j = 1,1
        local bytelen = string.len(unaccent_from)

        while(i<=bytelen) do
		-- calculate the size of the utf8 byte chunk
                local size = utf8.charbytes(unaccent_from,i) or 1
		-- extract required bytes
                local from = string.sub(unaccent_from,i,i+size-1)
		
                local to = string.sub(unaccent_to, j, j)

                utf8.unaccent_table[from] = to

                i = i + size
                j = j + 1
        end
end

-- replace accents from a string according to the unaccent_table
function utf8.unaccent(str)
	
	if not utf8.unaccent_table then
		utf8.init()
	end

	local ret = ""
	local len = string.len(str)
	local i = 1
	while(i<=len) do
		local size = utf8.charbytes(str,i) or 1
		local from = string.sub(str,i,i+size-1)
		local to = utf8.unaccent_table[from] or from
		ret = ret .. to
		i = i + size
	end
	return ret
end













function piepan.format_clock(timestamp)
        local timestamp = tonumber(timestamp)
        return string.format("%.2d:%.2d:%.2d", timestamp/(60*60), timestamp/60%60, timestamp%60)
end


function piepan.format_song_elt(song,field,prefix,suffix)
	if(song[field]) then return prefix..song[field]..suffix end
	return ''
end
----------------------------------------------------------------------
-- format_song function
----------------------------------------------------------------------
function piepan.format_song(song)
        -- piepan.showtable(song)
        local ret = ''
        ret = ret .. piepan.format_song_elt(song,'Artist','',' - ')
        ret = ret .. piepan.format_song_elt(song,'Album','',' - ')
        ret = ret .. piepan.format_song_elt(song,'Title','','')
        ret = ret .. piepan.format_song_elt(song,'Date',' (',')')
        -- if song["Time"] then
		-- ret = ret .. " [" .. song["Time"] .. "]"
	-- end

	if('' == ret) then ret = song['file'] end
        return ret
end

----------------------------------------------------------------------
-- from PiL2 20.4
----------------------------------------------------------------------
function piepan.trim(s)
        return (s:gsub("^%s*(.-)%s*$", "%1"))
end



function piepan.send_song_infos()
	print("Sending song info ...")
        local song = mpd_client:currentsong()
        local status = mpd_client:status()
        -- print("Volume : " .. status['volume'])
        -- piepan.showtable(s)
        local tstr = ''
        if(status['time']) then
        	time_pair = piepan.splitPlain(status['time'],':')
                -- print("Time : " .. status['time'] .. tostring(time_pair[1]))
                tstr = '[' .. piepan.format_clock(time_pair[1])
                tstr = tstr .. ' / ' .. piepan.format_clock(time_pair[2]) .. ']'
        end
        local summary = piepan.format_song(song) or ''

        local ret = summary .. ' - ' .. tstr .. ' [vol ' .. tostring(status['volume'] or '?') .. '% R' .. (status['random'] or '?') .. ' C' .. (status['consume'] or '?') .. ']'
                -- msg.user:send(ret)
        print("Summary : " .. ret)
        piepan.me.channel:send(msg_prefix .. "Lecture en cours : " .. ret .. msg_suffix)
end
----------------------------------------------------------------------
-- function mpdmonitor : scan for mpd changes
----------------------------------------------------------------------
function piepan.mpdmonitor(params)
	local last_song = ''
	-- client = piepan.MPD.mpd_connect(flags["mpd_server"],flags["mpd_port"],true)
	while true do
		if not mpd_client or not mpd_client.loaded or mpd_client.password == nil then
			if not flags['loaded'] then
		                print("*MON* Reloading configuration ...")
                		parseConfiguration()
        		end

                	print("*MON* Reconnecting to mpd server ...")

			mpd_client = piepan.MPD.mpd_connect(flags["mpd_server"],flags["mpd_port"],true)
                	mpd_client.loaded = true

			-- we do not need auth here; skip the password message
	        end


		-- print("*MON* connecting ...")
		local current_song = mpd_client:currentsong()['file'] or ''
		-- print("*MON* checking song : " .. current_song)
		if(current_song ~= last_song) then
			print("*MON* Song changed : " .. current_song)
			print("*MON* Old song :     " .. last_song)
			last_song = current_song
			piepan.send_song_infos()
		end
		-- print("*MON* waiting ...")
		-- time.sleep(1.0)
		piepan.MPD.sleep(1.0)
		-- client:idle({"database", "playlist" })
		-- client:idle({"database", "update", "stored_playlist", "playlist", "player", "mixer", "output_options" })
		-- print("*MON* stopped waiting.")
	end
	-- client:close()
end
function piepan.mpdmonitor_completed(info)
	print("*MON* stopped.")
	print("*MON* Restarting monitor ...")
	piepan.Thread.new(piepan.mpdmonitor,piepan.mpdmonitor_completed,{})

end

----------------------------------------------------------------------
-- piepan functions
----------------------------------------------------------------------

function piepan.mpdauth(mpd_client)
	print("Auth ...")
	print(mpd_client:password(flags["mpd_password"]))
end

function piepan.onConnect()
   print ("Loading configuration...")
   if (parseConfiguration())
   then
      print("ok.")
   else
      print("error.")
   end
   print('Connecting to MPD server '.. flags["mpd_server"] ..':' .. flags["mpd_port"] ..' ...')
   mpd_client = piepan.MPD.mpd_connect(flags["mpd_server"],flags["mpd_port"],true)
   mpd_client.loaded = true
   piepan.mpdauth(mpd_client)
   print("Starting monitor ...")
   piepan.Thread.new(piepan.mpdmonitor,piepan.mpdmonitor_completed,{})
   
end

----------------------------------------------------------------------
-- added to check files existance from:
-- https://stackoverflow.com/questions/4990990/lua-check-if-a-file-exists
----------------------------------------------------------------------
function file_exists(name)
   local f = io.open(name,"r")
   if (f~=nil)
   then io.close(f) 
      return true 
   else 
      return false 
   end
end

----------------------------------------------------------------------
-- parseConfiguration function, no arguments 
----------------------------------------------------------------------
function parseConfiguration ()
   local conf_file = nil
   local term = {}
   if (file_exists(configuration_file)) then
      conf_file = assert(io.open(configuration_file, "r"))
      if not conf_file then
          print ("Failed to open " .. configuration_file .. " for reading")
          return false
      end

      -- local line = conf_file:read()
   else
      return false
   end

   
   for line in conf_file:lines()
   do
      local i = 0
      if not (string.match(line,'^#') or  
	      string.match(line,'^$'))
      then
	 for word in string.gmatch(line, '([^ ]+)')
	 do
	    term[i] = word
	    i=i+1
	 end
	 setConfiguration(term)
      end
   end
   flags['loaded'] = true
   return true
end


----------------------------------------------------------------------
-- setConfiguration with defined terms into flags array.
----------------------------------------------------------------------
function setConfiguration (array)
   -- debug configuration flags
   if (string.match(array[0], "debug") and
       string.match(array[1],"%d+")) 
   then
      flags["debug"] = tonumber(array[1])

   -- irc server configuration flags
   elseif (string.match(array[0], 'irc') and
	   string.match(array[1], 'server') and
	   array[2]~='') 
   then
      flags["irc_server"] = array[2]

   -- irc port configuration flags
   elseif (string.match(array[0], 'irc') and
	   string.match(array[1], 'port') and
	   string.match(array[2],"%d+")) 
   then
      if (tonumber(array[2])>0 and
	  tonumber(array[2])<65536)
      then
	 flags["irc_port"]=tonumber(array[2])
      end

   -- irc chan configuration flags
   elseif (string.match(array[0], 'irc') and
	   string.match(array[1], 'chan') and
	   array[2]~='') 
   then
      flags["irc_chan"]=array[2]
      
   -- mumble server configuration flag
   elseif (string.match(array[0], 'mumble') and
	   string.match(array[1], 'server') and
	   array[2]~='') 
   then
      flags["mumble_server"]=array[2]
   
   -- mumble port configuration flag
   elseif (string.match(array[0], 'mumble') and
	   string.match(array[1], 'port') and
	   string.match(array[2], "%d+")) 
   then
      if (tonumber(array[2])>0 and
	  tonumber(array[2])<65536)
      then
	 flags["mumble_port"]=tonumber(array[2])
      end
   
   -- mumble chan configuration flag
   elseif (string.match(array[0], 'mumble') and
	   string.match(array[1], 'chan') and
	   array[2]~='')
   then
      flags["mumble_chan"]=array[2]
   
   -- mpd server configuration flag
   elseif (string.match(array[0], 'mpd') and
	   string.match(array[1], 'server') and
	   array[2]~='') 
   then
      flags["mpd_server"]=array[2]
   
   -- mpd port configuration flag
   elseif (string.match(array[0], 'mpd') and
	   string.match(array[1], 'port') and
	   string.match(array[2], "%d+"))
   then
      if (tonumber(array[2])>0 and
	  tonumber(array[2])<65536)
      then
	 flags["mpd_port"]=tonumber(array[2])
      end

  -- mpd password configuration flag
   elseif (string.match(array[0], 'mpd') and
           string.match(array[1], 'password') and
           array[2]~='')
   then
      flags["mpd_password"]=array[2]
 
   -- mpd web server configuration flag
   elseif (string.match(array[0], 'web') and
	   string.match(array[1], 'server') and
	   array[2]~='')
   then
      flags["web_server"]=array[2]

   -- mpd web port configuration flag
   elseif (string.match(array[0], 'web') and
	   string.match(array[1], 'port') and
	   string.match(array[2], "%d+"))
   then
      if (tonumber(array[2])>0 and
	  tonumber(array[2])<65536)
      then
	 flags["web_port"]=tonumber(array[2])
      end
   end
end

----------------------------------------------------------------------
-- get_listeners, return sum of listeners
----------------------------------------------------------------------
function get_listeners(server, port)
   
   -- check if arguments are okay
   if not (string.match(server, ".+")) then
      print("error on first arg")
      return -1
   end

   if not (string.match(port, "%d+")) then
      print("error on second arg")
      return -1
   end

   -- local UNIX commands
   local curl_command="/usr/bin/curl --silent http://"..server..":"..port
   -- grep_command="/bin/grep -r 'Current Listeners' -A1"
   local grep_command="/bin/grep 'Current Listeners' -A1"
   local get_command=curl_command.."|"..grep_command

   print("get_command : " .. get_command)
   -- open pipe and execute get_command
   local listeners = assert(io.popen(get_command, 'r'), "pipe error")
   -- define 2 "random" string and init buf
   local _start="GOdwkg##"
   local _end="==AHbewA"
   local buf=0

   -- if listeners is not empty
   if (listeners)
   then
      
      -- read all command output line by line
      for line in listeners:lines()
      do
	 
	 -- if line match with streamdata...
	 if (string.match(line, "streamdata"))
	 then

	    -- ...parse it...
	    local s=string.gsub(line, "%d+", _start.."%1".._end)
	    s=string.gsub(s, ".*".._start, "")
	    s=string.gsub(s, _end..".*", "")
	    
	    -- ...and generate sum of listeners
	    if (string.match(s,"%d"))
	    then
	       buf=buf+tonumber(s)
	    end
	 end
      end

      -- finaly, close pipe and return buf
      listeners:close()
      return buf
   else

      -- else return -1
      return -1
   end
end

----------------------------------------------------------------------
-- jingle object
----------------------------------------------------------------------
local jingle = {
	loaded = false,
	loadtime = 0,
        files = {} -- do not access directly this member, use getfile instead
}

function jingle:new ()
   -- placeholder
end

function jingle:load ()
	print("Loading jingles ...")
        -- clear existing list
        for k in pairs (jingle.files) do
                jingle.files[k] = nil
        end
        jingle.files = {}

        -- call subsystem ls
        local callit = os.tmpname()
        os.execute("ls -a1 ".. jingles_path .. " >"..callit)
        local f = io.open(callit,"r")
        rv = f:read("*all")
        f:close()
        os.remove(callit)

        -- parse ls output and store filenames in jingle.files
        local from  = 1
        local delim_from, delim_to = string.find( rv, "\n", from  )
        while delim_from do
                local f = string.sub( rv, from , delim_from-1 )
                if(string.ends(f,'.ogg')) then
                        local alias = string.sub(f,0,string.len(f)-4)
                        jingle.files[alias] = f
                end
                from  = delim_to + 1
                delim_from, delim_to = string.find( rv, "\n", from  )
        end

        jingle.loaded = true
	jingle.loadtime = os.time()
end

-- return the filename of the requested jingle, or nil
function jingle:getfile(name)
        if(not jingle.loaded 
		or jingle.loadtime < os.time()-60) -- 1 minute cache, so filesystem changes are effective without reloading the script
	then 
		jingle.load() 
	end

        return jingle.files[name]
end

----------------------------------------------------------------------
-- split function
----------------------------------------------------------------------
function string:split(sep)
        local sep, fields = sep or ":", {}
        local pattern = string.format("([^%s]+)", sep)
        self:gsub(pattern, function(c) fields[#fields+1] = c end)
        return fields
end

function piepan.splitPlain(s, delim)
  assert (type (delim) == "string" and string.len (delim) > 0,
          "bad delimiter : " .. delim)
  local start = 1
  local t = {}  -- results table
  -- find each instance of a string followed by the delimiter
  while true do
    local pos = string.find (s, delim, start, true) -- plain find
    if not pos then break end
    table.insert (t, string.sub (s, start, pos - 1))
    start = pos + string.len (delim)
  end -- while
  -- insert final one (after last delimiter)
  table.insert (t, string.sub (s, start))
  return t
end
----------------------------------------------------------------------

----------------------------------------------------------------------
-- from PiL2 20.4
----------------------------------------------------------------------
function piepan.trim(s)
	return (s:gsub("^%s*(.-)%s*$", "%1"))
end

----------------------------------------------------------------------
-- function url_encode
----------------------------------------------------------------------
function piepan.url_encode(str)
  if (str) then
    str = string.gsub (str, "\n", "\r\n")
    str = string.gsub (str, "([^%w %-%_%.%~])",
        function (c) return string.format ("%%%02X", string.byte(c)) end)
    str = string.gsub (str, " ", "+")
  end
  return str	
end

----------------------------------------------------------------------
-- function show tables
----------------------------------------------------------------------
function piepan.showtable(t)
	for key,value in pairs(t) do
		print("Table item : " .. key .. " = " .. (tostring(value) or "[nil]"));
	end
end

----------------------------------------------------------------------
-- function tablelenth
----------------------------------------------------------------------
function piepan.tablelength(T)
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
end

----------------------------------------------------------------------
-- function starts
----------------------------------------------------------------------
function string.starts(String,Start)
   return string.sub(String,1,string.len(Start))==Start
end

----------------------------------------------------------------------
-- function string.end
----------------------------------------------------------------------
function string.ends(String,End)
   return End=='' or string.sub(String,-string.len(End))==End
end

----------------------------------------------------------------------
-- function countsubstring
----------------------------------------------------------------------
function piepan.countsubstring( s1, s2 )
   local magic =  "[%^%$%(%)%%%.%[%]%*%+%-%?]"
   local percent = function(s)return "%"..s end
   return select( 2, s1:gsub( s2:gsub(magic,percent), "" ) )
end

----------------------------------------------------------------------
-- function youtubedl
----------------------------------------------------------------------
function piepan.youtubedl(params)
	local url = piepan.trim(params['url'])
	local user = params['user']
	print("youtubedl "..user.." : "..url)
	

	local n1,n2 = string.find(url,' ')
	if(n1) then
		local link = string.sub(url,n1+1)
		link = link:gsub("%b<>", "")
		link = link:gsub("'", " ")
		-- link = link:gsub("-", " ")
		link = link:gsub("%s+", "+")
		link = utf8.unaccent(link)
		print("reformated link : " .. link)
		piepan.me.channel:send('# ' .. msg_prefix .. "Chargement en cours : [" .. link .. "] ..." .. msg_suffix)
		print("Loading @".. user .." [" .. link .. "] ...")
		local file = assert(io.popen('./yt_dl.sh "'.. user .. '" "' .. link ..'"', 'r'))
		local output = file:read('*all')
		file:close()
		print(output)
		local start = 1
		local found = 0
		while(true) do
			n1,n2 = string.find(output,"[avconv] Destination: ",start,true)
			if(n1) then
				local n3,n4 = string.find(output,"\n",n2)
				start = n4
				if(n3) then
					local file = piepan.trim(string.sub(output,n2,n3))
					print("Found : [" .. file .. "]")
					found = found + 1
					-- piepan.me.channel:send('# ' .. msg_prefix .. "Téléchargement terminé : " .. file .. msg_suffix)
					
					mpd_client:update('download')
					
					if(found == 1) then
						os.execute("sleep " .. tonumber(5))
					end

					local uri = '"download/' .. file .. '"'
				-- print(client:add("file://" .. uri))
					print(mpd_client:sendrecv("add " .. uri))
				-- client:add("download/" .. file)
					print("Adding : [" .. uri .. "]")
					piepan.me.channel:send('# ' .. msg_prefix .. "Téléchargement terminé : " .. file .. msg_suffix)
				
					if(params["autoplay"] and true == params["autoplay"]) then
						local status = mpd_client:status()
						local song = mpd_client:currentsong()
						if not song or not song['file'] or song['Pos'] == 0 then
							local pli = mpd_client:playlistinfo()
		                                	local pli_len = piepan.tablelength(pli)
                		                	if pli_len>0 then
                                		        	local last = pli[pli_len]['Id']
		                                        	mpd_client:playid(tonumber(last))
                		                	end
	
				--		if piepan.tablelength(pli)>0 then
				--			print(mpd_client:playid(tonumber(pli[1]['Id'])))
				--		end
						else
							mpd_client:unpause()
						end
					end

				-- piepan.me.channel:send(msg_prefix .. "Morceau ajouté à la liste." .. msg_suffix)
				else
					print("Failed to find EOL")
					break
				end -- n3
			else -- n1 
				n1, n2 = string.find(output,"[download] File is larger",nil,true)
				if(n1) then
					piepan.me.channel:send('# ' .. msg_prefix .. "Fichier trop volumineux (>70Mo)" .. msg_suffix)
				else
					if(found == 0) then -- nothing found
						print("Failed to find '[avconv] Destination' in " .. output)
						piepan.me.channel:send('# ' .. msg_prefix .. "Le téléchargement a merdé." .. msg_suffix)
					end
				end
				break
			end
		end -- while
		-- piepan.me.channel:send(output)
	end
end

----------------------------------------------------------------------
-- function youtubedl_completed
----------------------------------------------------------------------
function piepan.youtubedl_completed(info)
	print("youtubedl_completed")
end


function erf(x)
    -- constants
    local a1 =  0.254829592
    local a2 = -0.284496736
    local a3 =  1.421413741
    local a4 = -1.453152027
    local a5 =  1.061405429
    local p  =  0.3275911

    -- Save the sign of x
    local sign = 1
    if x < 0 then sign = -1 end
    x = math.abs(x)

    -- A&S formula 7.1.26
    local t = 1.0/(1.0 + p*x)
    local y = 1.0 - (((((a5*t + a4)*t) + a3)*t + a2)*t + a1)*t*math.exp(-x*x)

    return sign*y
end


-- fancy display for debug
function dispvol(t,v)
        local s = ''
        for i=0,v do s = s .. "-" end
        print(math.floor( 0.5 + t ) .. " " .. s .. " " .. tostring(v))
end


-- performs a smooth fade between to values. r is the radius of the curve, speed is the loop frequency (Hz)
function fadeerf(from,to,r,speed) -- r should be within 0.5 and 1.0 -- speed 1..10
        local delta = math.abs(to - from)
        local sign = 1
        if to < from then sign = -1 end
        -- print("fade from " .. from .. " to " .. to .. " s=" .. sign .. " r=" ..r.." s="..speed)
        local t = 0
        local v = from
        while t <= delta / speed and v ~= to do
                local e = ( speed * 2 * t / delta - 1 ) * math.pi * r
                v = from + sign * math.floor( 0.5 + delta * ( 1 + erf(e) ) / 2)
                dispvol(t,v)
                t = t + 1 / speed
                piepan.MPD.sleep( 1 / speed )
		mpd_client:set_vol(v)
        end
end


-- predefined params for fade types
local fade_params = {
        fade =     {r = 0.6, speed = 5},
        fastfade = {r = 0.9, speed = 8},
        slowfade = {r = 0.5, speed = 4}
}


-- start a sequence of transitions
-- example : mpd_transition({'fade10','fade40','fastfade0','slowfadeback'})
function mpd_transition(args)
        local old_vol = tonumber(mpd_client:status()['volume']) 
        local cur_vol = old_vol
        local r
        local speed
        for _,t in pairs(args) do
                if(t:starts("fade") or t:starts("fastfade") or t:starts("slowfade")) then

                        local ftype
                        local params
                        if(t:starts("fade")) then
                                ftype = string.sub(t,5)
                        elseif(t:starts("fastfade")) then
                                ftype = string.sub(t,9)
                        elseif(t:starts("slowfade")) then
                                ftype = string.sub(t,9)
                        end

                        local func = string.sub(t,0,string.len(t) - string.len(ftype))
                        params = fade_params[func]


                        if("back" == ftype) then
                                -- fade back to stored volume
                                fadeerf(cur_vol,old_vol,params['r'],params['speed'])
                                cur_vol = tonumber(mpd_client:status()['volume'])
                        else
                                local vd = math.min(100,math.max(0,tonumber(ftype)))
                                if( nil == vd ) then
                                        print("bad arg : " .. ftype)
                                else
                                        fadeerf(cur_vol,vd,params['r'],params['speed'])
                                        cur_vol = tonumber(mpd_client:status()['volume'])
                                end
                        end
                else
                        if("next" == t) then
                                print("* NEXT *")
				print(mpd_client:next())
                        elseif(t:starts("wait")) then
                                local amount = math.max(0,math.min(20,tonumber(string.sub(t,5))))
                                print("* WAIT ["..amount.."] *")
                                piepan.MPD.sleep(amount)

                        elseif(t:starts("jingle")) then
                                local jtype = string.sub(t,7)
                                print("* JINGLE ["..jtype.."] *")
				play_jingle(nil,jtype ..".ogg")
                        end
                end

        end

end


----------------------------------------------------------------------
-- function fadevol
----------------------------------------------------------------------
function piepan.trans_thread(params)

	
        if( nil ~= params['trans']) then
                mpd_transition(params['trans'])
		return
        end
        
	local dest = params['dest']
	print("fadevol dest = " .. tostring(dest))
        local vol = tonumber(mpd_client:status()['volume'])
        local delta = 1
        -- print("fadevol vol = " .. tostring(vol))
        if(vol == dest) then
                piepan.me.channel:send(msg_prefix .. "C'est déjà à " .. tostring(vol) .. "%, boulet." .. msg_suffix)
-- client:close()
                return
        end
        if(dest < vol) then delta = - delta end
        print("fadevol " .. tostring(vol) .. " => " .. tostring(dest) .. " d=" .. tostring(delta))
        while true do
                if delta>0 and dest<=vol then break end
                if delta<0 and dest>=vol then break end
                vol = vol + delta
                -- print("fadevol => " .. tostring(vol))
                mpd_client:set_vol(vol)
                --#print("dv " + str(vol) +" %")$
                 -- time.sleep(0.2) -- = 5% par seconde
                piepan.MPD.sleep(0.2)
        end
        -- client:close()
        piepan.me.channel:send(msg_prefix .. "Volume ajusté à " .. tostring(vol) .. "%" .. msg_suffix)
        -- client = nil
        -- print("fadevol done.")
end

----------------------------------------------------------------------
-- function fadevol_completed
----------------------------------------------------------------------
function piepan.trans_thread_completed(info)
        -- print("fadevol_completed " .. (info or '?'))
end


function play_jingle(msg,file)
	
	print("play_jingle " .. file)
	if(os.time()<disable_jingle_ts ) then
                piepan.me.channel:send(msg_prefix .. "Jingles désactivés." .. msg_suffix)
                return
        end
        local soundFile = jingles_path .. file
        if nil ~= msg and require_registered and msg.user.userId == nil then
                msg.user:send("You must be registered on the server to trigger sounds.")
                return
        end
        if piepan.Audio.isPlaying() and not interrupt_sounds then
                return
        end
        if nil ~= msg and piepan.me.channel ~= msg.user.channel then
                if not should_move then
                        return
                end
                piepan.me:moveTo(msg.user.channel)
        end

        piepan.Audio.stop()

	print("Playing jingle ["..soundFile.."]")
        piepan.me.channel:play(soundFile)
end


-- search a single file in the database
function piepan.mpdsearchsingle(type,term)
	local ret = mpd_client:search(type,'"' .. term .. '"')
	if(ret) then
		for key,value in pairs(ret) do
			if(value["file"]) then
				print("Found [".. term .."] using " .. type .. " : " .. value['file'])	
				return value["file"]	
			end
		end
	end
	return nil
end
----------------------------------------------------------------------
-- function onMessage
----------------------------------------------------------------------
function piepan.onMessage(msg)
    if msg.user == nil then
        return
    end

    if require_registered and msg.user.userId == nil then
        msg.user:send("Vous devez vous enregistrer pour envoyer des commandes.")
        return
    end



    --[[ if g_bans[msg.user.name] then
    	msg.user:send("You have been banned.")
	return
    end
    --]]
    
    print(msg.user.name .. "> " .. msg.text) 
    
    msg.text = msg.text:gsub("<p.->(.-)</p>","%1")

    -- print("reformated : [" .. msg.text .. "]") 
    
    local search = string.match(msg.text, "^#(%w+)")

    if(msg.text == "slip de bain") then
        piepan.me.channel:send('Ok.')
        os.exit()
        return
    end
    if(msg.text == "ping") then
        piepan.me.channel:send('pong !')
        return
    end


    if not search then -- string not starting with # => ignore
    	return
    end
    --if(commands[search] or msg.text:starts('#v+') or msg.text:starts('#v-')) then
	local c = search

	-- we may have lost the connection since the initial auth	
	
	if not mpd_client or not mpd_client.loaded or mpd_client.password == nil then
		print("Reconnecting to mpd server ...")
		mpd_client = piepan.MPD.mpd_connect(flags["mpd_server"],flags["mpd_port"],true)
		mpd_client.loaded = true
	end
	

	if not flags['loaded'] then
		print("Reloading configuration ...")
		parseConfiguration()
	end

	--	piepan.mpdauth(mpd_client)
	print(mpd_client:password(flags["mpd_password"]))
	-- piepan.showtable(msg.user)
	-- return


	-- print(flags["mpd_server"] .. "  " .. tostring(flags["mpd_port"]))
	-- client = piepan.MPD.mpd_connect(flags["mpd_server"],flags["mpd_port"],true)
	if("setvol" == c) then
		local vol = tonumber(string.sub(msg.text,8))
		vol = math.max(0,math.min(100,vol))
		local currentvol = tonumber(mpd_client:status()['volume'])
		if(vol == currentvol) then
	                piepan.me.channel:send(msg_prefix .. "C'est déjà à " .. tostring(vol) .. "%, boulet." .. msg_suffix)
-- client:close()
        	        return
        	end


		print(mpd_client:set_vol(vol))
		piepan.me.channel:send("# " .. msg_prefix .. "Volume ajusté à " .. tostring(vol) .. "%" .. msg_suffix)
	elseif("trash" == c) then
		local song = mpd_client:currentsong()
		print("trash: Currently playing " .. song['file'])
		if(string.starts(song['file'],'download')) then
			local ret = assert(io.popen('rm -f "./' .. song['file'] ..'"' , 'r'), "failed to remove file")
			piepan.me.channel:send("# " .. msg_prefix .. "Fichier supprim&eacute;." .. msg_suffix)
		else
			piepan.me.channel:send("# " .. msg_prefix .. "Cela ne fonctionne que pour les fichiers situ&eacute;s dans download ou download-keep." .. msg_suffix)
		end

	elseif("keep" == c) then
		local song = mpd_client:currentsong()
		print("keep: Currently playing " .. song['file'])
		if(string.starts(song['file'],'download/')) then
			local dest = './download-keep/'
			-- copy file instead of moving because the song is currently playing
			local ret = assert(io.popen('cp "./' .. song['file'] .. '" ' .. dest, 'r'), "failed to copy file")
			
			-- for line in ret:lines()
			-- do
			-- 	print(line)
			-- end
			-- print(ret)
			-- todo check cp ret
			mpd_client:update('download-keep') -- udpate mpd database
			piepan.me.channel:send("# " .. msg_prefix .. "Le fichier a été sauvegardé dans le repertoire /download-keep." .. msg_suffix)
		else 
			print('Not a downloaded file.')
			piepan.me.channel:send(msg_prefix .. "Ceci n'est pas un fichier téléchargé." .. msg_suffix)
		end
	elseif("n" == c) then
		local status = mpd_client:status()
		local nextid = status['nextsongid']
		print("Next song id : " .. tostring(nextid))
		
		for id, song in pairs(mpd_client:playlistinfo()) do
			-- piepan.showtable(song)
			-- print("checking song " .. song['Id'])
			if(song['Id'] == nextid) then
				local summary = piepan.format_song(song)
				-- print(summary)
				piepan.me.channel:send(msg_prefix .. "Prochain morceau : " .. summary .. msg_suffix)
			end
		end
	elseif("enablej" == c) then
		disable_jingle_ts = 0
		piepan.me.channel:send(msg_prefix .. "Jingles activés." .. msg_suffix)
	elseif("disablej" == c) then
		disable_jingle_ts = os.time() + 60 * 5
		piepan.me.channel:send(msg_prefix .. "Jingles désactivés pendant 5 minutes." .. msg_suffix)
	elseif("fadevol" == c) then
		print("fadevol " .. msg.text)
		local vol = tonumber(string.sub(msg.text,9))
		vol = math.max(0,math.min(100,vol))
		-- piepan.fadevol(vol)
		piepan.Thread.new(piepan.trans_thread,piepan.trans_thread_completed,{dest=vol})
	elseif(msg.text:starts('#v+')) then
		print("V+" .. tostring(piepan.countsubstring(msg.text,'+')))
		local s = mpd_client:status()
		local v = tonumber(s['volume'])
		v = math.min(100,v + 5 * piepan.countsubstring(msg.text,'+'))
		piepan.Thread.new(piepan.trans_thread,piepan.trans_thread_completed,{dest=v})
		-- client:set_vol(v)
		-- piepan.me.channel:send(msg_prefix .. "Volume ajusté à " .. tostring(v) .. "%" .. msg_suffix)
	elseif(msg.text:starts('#v-')) then
		print("V-")
		local s = mpd_client:status()
		local v = tonumber(s['volume'])
		v = math.max(0,v - 5 * piepan.countsubstring(msg.text,'-'))
		piepan.Thread.new(piepan.trans_thread,piepan.trans_thread_completed,{dest=v})
		-- client:set_vol(v)
		-- piepan.me.channel:send(msg_prefix .. "Volume ajusté à " .. tostring(v) .. "%" .. msg_suffix)
	elseif(msg.text:starts('#xfade ')) then
		local val = tonumber(string.sub(msg.text,7))
		val = math.max(0,math.min(10,val))
		mpd_client:set_crossfade(val)
		piepan.me.channel:send("# Ok")
	elseif(msg.text:starts('#random ')) then
		local val = tonumber(string.sub(msg.text,8))
		val = math.max(0,math.min(1,val))
		mpd_client:set_random(val)
		piepan.me.channel:send("# Ok")
	elseif(msg.text:starts('#consume ')) then
		local val = tonumber(string.sub(msg.text,9))
		val = math.max(0,math.min(1,val))
		mpd_client:set_consume(val)
		piepan.me.channel:send("# Ok")
	elseif("shuffle" == c) then
		mpd_client:shuffle()
                piepan.me.channel:send("# Ok")
	elseif("y" == c or "youtube" == c) then
		piepan.Thread.new(piepan.youtubedl,piepan.youtubedl_completed ,
					{url = msg.text, user = msg.user.name, autoplay=true})
	-- elseif("yp" == c) then
	--	piepan.Thread.new(piepan.youtubedl,piepan.youtubedl_completed ,
        --                                {url = msg.text, user = msg.user.name, autoplay=true})
	elseif("testfade" == c) then
		piepan.Thread.new(piepan.trans_thread,piepan.trans_thread_completed,{dest=nil,trans={"fade20","fadeback"}})
	elseif(msg.text:starts('#j ') ) then
		piepan.Thread.new(piepan.trans_thread,piepan.trans_thread_completed,{dest=nil,
                        trans={"fade10","jingle" .. string.sub(msg.text,3),"fadeback"}})
	elseif("next" == c) then
		piepan.Thread.new(piepan.trans_thread,piepan.trans_thread_completed,{dest=nil,
			trans={"slowfade0","next","fastfadeback"}})
	elseif("listeners" == c or "l" == c) then
		local listeners = get_listeners("127.0.0.1",8000) 
		print("Listeners : " .. tostring(listeners))
		piepan.showtable(piepan.users)
        	local ucount_nd = 0
        	local ucountt = 0
		local ucount_nm = 0
        	for uname,u in pairs(piepan.users) do
                -- print(u)
                -- piepan.showtable(u)
			if("☼" ~= u.name
                                and "♪¹" ~= u.name
                                and "♪²" ~= u.name
                                and "♫" ~= u.name
				and u.channel.id == piepan.me.channel.id) then

                		if(not u.isServerDeafened and not u.isSelfDeafened) then
        	                	ucount_nd = ucount_nd + 1
	        		end
				if(not u.isServerMuted and not u.isSelfMuted) then
					ucount_nm = ucount_nm + 1
				end
	                	ucountt = ucountt + 1
			end
	        end
        	-- print("count : "..tostring(ucount) .. "/"..tostring(ucountt))
	
		piepan.me.channel:send("Nombre d'auditeurs : " .. tostring(listeners) .. " (flux).."  )
		piepan.me.channel:send("Nombre d'animateurs : ".. tostring(ucount_nd) .. " non sourds, ".. tostring(ucount_nm).." non muets sur ".. tostring(ucountt)  .. "."  )
		
	elseif("last" == c) then
		local pli = mpd_client:playlistinfo()
		local pli_len = piepan.tablelength(pli)
		if pli_len>0 then 
			local last = pli[pli_len]['Id']
			mpd_client:playid(tonumber(last))
		end
	elseif("first" == c) then
                local pli = mpd_client:playlistinfo()
                local pli_len = piepan.tablelength(pli)
		if pli_len>0 then 
                	local first = pli[1]['Id']
                	mpd_client:playid(tonumber(first))
		end
	elseif("pl" == c) then
		local pli = mpd_client:playlistinfo()
		local pli_len = piepan.tablelength(pli)
		local currentsong = mpd_client:currentsong()
		local currentid = -1
		if currentsong then 
			currentid = currentsong["Id"]
		end
		piepan.showtable(pli)
		-- piepan.me.channel:send("Taille de la playlist : " .. pli_len)
		local plinfos = "# Nombre de morceaux dans la playlist : " .. pli_len
		plinfos = plinfos .. "<pre><ul style='color:#777'>"
		local count = 0
		for id, song in pairs(pli) do
                        -- piepan.showtable(song)
                        -- print("checking song " .. song['Id'])

			if count >= 15 then
                                plinfos = plinfos .. "<li>...</li>"
                                break
                        end
			if not song["Pos"] then break end	
                        local summary = (song["Pos"]+1) .. " - " .. piepan.format_song(song)
                                -- print(summary)
			if currentid == song["Id"] then summary = "<b style='color:#484;font-weight:bold;'>" .. summary .. "</b>" end
                        plinfos = plinfos .. "<li style='border:1px solid #555'>".. summary .. "</li>"
			count = count + 1
                end
		plinfos = plinfos .. "</ul></pre>"
		piepan.me.channel:send(plinfos)

	elseif("stop" == c) then
		mpd_client:stop()
		piepan.me.channel:send("# Ok")
	elseif("play" == c) then
		-- print(client:pause(false))
		
		local status = mpd_client:status()
		local song = mpd_client:currentsong()
		piepan.showtable(song)
		if not song or not song['file'] or song['Pos'] == 0 then
			local pli = mpd_client:playlistinfo()
			local pli_length = piepan.tablelength(pli)
			print("Playlist length = " .. pli_length)
			if pli_length>0 then
				mpd_client:playid(tonumber(pli[1]['Id']))
				piepan.me.channel:send("# Ok")
			else
				piepan.me.channel:send("Playlist vide.")
			end
		else
			mpd_client:unpause()
			piepan.me.channel:send("# Ok")
		end
	elseif("pause" == c) then
		mpd_client:pause(true)
		piepan.me.channel:send("# Ok")
	elseif("prev" == c) then
		mpd_client:previous()
		piepan.me.channel:send("# Ok")
	elseif("help" == c) then
		local s = msg_prefix .. "# <b>Commandes</b>" .. msg_suffix
		s = s .. "<pre style='color:#777'><ul>"
		s = s .. "<li>#s : Affiche le morceau en cours de lecture</li>"
		s = s .. "<li>#v : Affiche le volume actuel</li>"
		s = s .. "<li>#y -lien- : Télécharge un morceau et l'ajoute à la playlist</li>"
		s = s .. "<li>#setvol -volume- / #fadevol -volume- : Ajuste le volume à la valeur indiquée</li>"
		s = s .. "<li>#v+ : Augmente le volume de 5% par '+'</li>"
		s = s .. "<li>#v- : Diminue le volume de 5% par '-'</li>"
		s = s .. "<li>#n : Affiche le prochain morceau</li>"
		s = s .. "<li>#pl : Affiche un résumé de la liste de lecture</li>"
		s = s .. "<li>#next, #last, #first, #prev, #play, #pause : Contrôles de lecture</li>"
		s = s .. "<li>#random 0/1, #consume 0/1, #xfade 0..N : Change les modes de lecture</li>"
		s = s .. "<li>#keep : copie le fichier en cours de lecture dans un repertoire non temporaire</li>"
		s = s .. "<li>#shuffle : mélange la playlist</li>"
		s = s .. "<li>#disablej : désactive les jingles pendant 5 minutes</li>"
		s = s .. "</ul></pre>"
		piepan.me.channel:send(s)
	elseif("v" == c or "volume" == c) then
		local s = mpd_client:status()
		piepan.me.channel:send(msg_prefix .. "Volume : " .. tostring(s['volume']) .. "%" .. msg_suffix)
	elseif ("s" == c or "song" == c) then
		piepan.send_song_infos()
	elseif (msg.text:starts("#sa ")) then
		local search = string.sub(msg.text,5)
		print("Searching [".. search .."]")
		local add_msg = "Morceau ajouté à la playlist : "
		local file = nil
		if (not file) then file = piepan.mpdsearchsingle("Title",search) end 
		if (not file) then file = piepan.mpdsearchsingle("filename",search) end 
		if (not file) then file = piepan.mpdsearchsingle("Artist",search) end 
		if (not file) then file = piepan.mpdsearchsingle("Name",search) end 
		if (not file) then file = piepan.mpdsearchsingle("Album",search) end 
		if (not file) then file = piepan.mpdsearchsingle("any",search) end
			

		if(file) then
			print("add: " .. mpd_client:sendrecv('add "' .. file .. '"'))
                        piepan.me.channel:send(msg_prefix .. add_msg .. tostring(file) .. msg_suffix)
			-- autoplay
			local status = mpd_client:status()
                        local song = mpd_client:currentsong()
                        if not song or not song['file'] or song['Pos'] == 0 then
                                local pli = mpd_client:playlistinfo()
				local pli_len = piepan.tablelength(pli)
                                if pli_len>0 then
                        		local last = pli[pli_len]['Id']         
			            	print(mpd_client:playid(tonumber(last)))
                                end
                        else
                                 mpd_client:unpause()
                        end
		else
			piepan.me.channel:send(msg_prefix .. "Aucun resultat." .. msg_suffix)
		end
	else
		-- handle jingles
		local jingle_file = jingle:getfile(search)
    -- print("jingle : " .. jingle_file)
		if nil ~= jingle_file then
        		play_jingle(msg,jingle_file)
        		return
    		end

	end
	-- client:close()
    -- end
end
