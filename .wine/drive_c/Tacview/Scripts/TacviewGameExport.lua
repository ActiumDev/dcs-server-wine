-- Tacview ACMI - Universal Flight Analysis Tool 1.7.6
-- Flight Data Recorder for DCS World Export LUA Environment
-- Copyright (C) 2006-2018 - Raia Software Inc.
-- All rights reserved.

do
	if isTacviewModuleInitialized~=true then

		-- Protection against multiple references (typically wrong script installation)

		isTacviewModuleInitialized=true

		-- Debug info to detect invalid installation

		local scriptFullPath = debug.getinfo(1).source
		log.write('TACVIEW.EXPORT.LUA',log.INFO,'Starting ['..scriptFullPath..']')

		-- Load Tacview DLL from Saved Games folder

		local tacviewModPath = lfs.writedir()..'Mods\\tech\\Tacview\\bin\\'
		package.cpath = package.cpath..';'..tacviewModPath..'?.dll;'
		log.write('TACVIEW.EXPORT.LUA',log.INFO,'Loading C++ flight data recorder from ['..tacviewModPath..']')

		local status,tacview = pcall(require,'tacview')

		-- Load Tacview DLL from Tacview installation folder
		-- (failsafe in case of Unicode characters in Saved Games path)

		if not status then

			tacviewModPath = os.getenv('TACVIEW_DCS2ACMI_PATH')..'Mods\\tech\\Tacview\\bin\\'
			package.cpath = package.cpath..';'..tacviewModPath..'?.dll;'
			log.write('TACVIEW.EXPORT.LUA',log.INFO,'Loading C++ flight data recorder from ['..tacviewModPath..']')

			status,tacview = pcall(require,'tacview')

		end

		-- Register Callbacks in DCS World Export environment

		local tacviewName = 'Tacview 1.9.5.200 C++ flight data recorder'

		if status then

			-- (Hook) Called once right before mission start.

			do
				local PrevLuaExportStart=LuaExportStart

				LuaExportStart=function()
				
					tacview.ExportStart()

					if PrevLuaExportStart then
						PrevLuaExportStart()
					end
				end
			end

			-- (Hook) Called at the BEGINING of the current simulation frame.

			do
				local PrevLuaExportBeforeNextFrame=LuaExportBeforeNextFrame

				LuaExportBeforeNextFrame=function()

					-- log.write('TACVIEW.EXPORT.LUA',log.INFO,string.format("calling tacview.ExportUpdateBegin(%g) clock=%.6f",LoGetModelTime(), os.clock()))

					tacview.ExportUpdateBegin()

					if PrevLuaExportBeforeNextFrame then
						PrevLuaExportBeforeNextFrame()
					end
				end
			end

			-- (Hook) Called at the END of the current simulation frame.

			do
				local PrevLuaExportAfterNextFrame=LuaExportAfterNextFrame

				LuaExportAfterNextFrame=function()

					-- log.write('TACVIEW.EXPORT.LUA',log.INFO,string.format("calling tacview.ExportUpdateEnd(%g) clock=%.6f",LoGetModelTime(),os.clock()))

					tacview.ExportUpdateEnd()

					if PrevLuaExportAfterNextFrame then
						PrevLuaExportAfterNextFrame()
					end
				end
			end

			-- (Hook) Called right after mission end.

			do
				local PrevLuaExportStop=LuaExportStop

				LuaExportStop=function()

					tacview.ExportStop()

					if PrevLuaExportStop then
						PrevLuaExportStop()
					end
				end
			end

			log.write('TACVIEW.EXPORT.LUA',log.INFO,tacviewName..' successfully loaded.')

		-- Failed to load Tacview DLL

		else

			log.write('TACVIEW.EXPORT.LUA',log.ERROR,'Failed to load '..tacviewName..'.')
			tacview = nil

		end
	end
end
