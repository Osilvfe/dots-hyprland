HOME = os.getenv("HOME")

function is_file_exists(name)
   local f = io.open(name, "r")
   if f ~= nil then
      io.close(f)
      return true
   else
      return false
   end
end

function create_if_not_exists(path)
   if not is_file_exists(path) then
      os.execute("mkdir -p \"$(dirname \"" .. path .. "\")\"")
      os.execute("echo '-- This file will not be overwritten across dots-hyprland updates.\n-- The file name is for the sake of organization and does not matter\n-- See the corresponding files in ~/.config/hypr/hyprland for examples' > \"" .. path .. "\"")
      return true
   end
   return false
end

function workspace_in_group(i)
    local monitors = hl.get_monitors()
    local focused = hl.get_active_monitor()
    local monitorIndex = 0
    for idx, mon in ipairs(monitors) do
        if mon.name == focused.name then
            monitorIndex = idx - 1
            break
        end
    end
    return monitorIndex * workspaceGroupSize + i
end
