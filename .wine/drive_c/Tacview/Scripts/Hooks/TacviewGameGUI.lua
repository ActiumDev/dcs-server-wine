-- Tacview ACMI - Universal Flight Analysis Tool 1.7.6
-- Flight Data Recorder for DCS World Game GUI LUA Environment
-- Copyright (C) 2006-2018 - Raia Software Inc.
-- All rights reserved.

do
	-- Debug info to detect invalid installation

	local scriptFullPath = debug.getinfo(1).source
	log.write('TACVIEW.GUI.LUA',log.INFO,'Starting ['..scriptFullPath..']')

	-- Load Tacview DLL from Saved Games folder

	local tacviewModPath = lfs.writedir()..'Mods\\tech\\Tacview\\bin\\'
	package.cpath = package.cpath..';'..tacviewModPath..'?.dll;'
	log.write('TACVIEW.GUI.LUA',log.INFO,'Loading C++ flight data recorder from ['..tacviewModPath..']')

	local status,tacview = pcall(require,'tacview')

	-- Load Tacview DLL from Tacview installation folder
	-- (failsafe in case of Unicode characters in Saved Games path)

	if not status then

		tacviewModPath = os.getenv('TACVIEW_DCS2ACMI_PATH')..'Mods\\tech\\Tacview\\bin\\'
		package.cpath = package.cpath..';'..tacviewModPath..'?.dll;'
		log.write('TACVIEW.GUI.LUA',log.INFO,'Loading C++ flight data recorder from ['..tacviewModPath..']')

		status,tacview = pcall(require,'tacview')

	end

	-- Register Callbacks in DCS World GUI environment

	local tacviewName = 'Tacview 1.9.5.200 C++ flight data recorder';

	if status then

		local tacviewCallbacks = {}

		function tacviewCallbacks.onMissionLoadEnd()
			tacview.GUIStart()
		end

		function tacviewCallbacks.onSimulationStop()
			tacview.GUIStop()
		end

		function tacviewCallbacks.onSimulationFrame()
			-- log.info(string.format("LUA heap size: %d KiB",collectgarbage("count")));
			tacview.GUIUpdate()
		end

		function tacviewCallbacks.onPlayerConnect(id)
			tacview.GUIOnPlayerConnect(id)
		end

		function tacviewCallbacks.onPlayerDisconnect(id,err_code)
			tacview.GUIOnPlayerDisconnect(id)
		end

		DCS.setUserCallbacks(tacviewCallbacks)

		log.write('TACVIEW.GUI.LUA',log.INFO,tacviewName..' successfully loaded.')

	-- Failed to load Tacview DLL

	else

		log.write('TACVIEW.GUI.LUA',log.ERROR,'Failed to load '..tacviewName..'.')
		tacview = nil

	end
end
