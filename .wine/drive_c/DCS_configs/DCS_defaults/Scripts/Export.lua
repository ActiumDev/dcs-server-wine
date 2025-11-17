-- try to import Tacview, failing silently if Tacview is not installed
pcall(dofile, lfs.writedir() .. "Scripts/TacviewGameExport.lua")
