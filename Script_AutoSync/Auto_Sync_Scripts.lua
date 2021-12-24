--[[
Automatically synchronizes CE scripts with scripts saved elsewhere on the PC

2021-12-17, sandsalamand, based on ametalon's create_script
]]
package.preload["ce.auto_sync"] = function(...)
    local _m = {}
    local default_code = [[
  [ENABLE]
  
  [DISABLE]
  
  ]]
    ----------------------------------------Options-------------------------------------------
    local timerInterval = 300
    ------------------------------------------------------------------------------------------

    --TODO: try changing function names to start with a capital
    local recordIdList = {}
    local recordList = {}
    local pathList = {}
    local tableFileName = "syncList.txt"
    SyncTimer = nil

    --[[currently unnecessary
    local function getScriptRecord(scriptName)
        local scriptRecord = nil
        local addressList = getAddressList()
        if addressList.Count >= 1 then
        scriptRecord = addressList.getMemoryRecordByDescription(scriptName)
        end
        if scriptRecord == nil then
            scriptRecord = addressList.createMemoryRecord()
            scriptRecord.Description = scriptName
        end
        scriptRecord.Type = 11 --11 is autoAssembler
        return scriptRecord
    end ]]

    -- Escape special pattern characters in string to be treated as simple characters
    local function escape_magic(s)
        local MAGIC_CHARS_SET = '[()%%.[^$%]*+%-?]'
        if s == nil then return end
        return (s:gsub(MAGIC_CHARS_SET,'%%%1'))
    end

    -- Returns an iterator to split a string on the given delimiter (comma by default)
    function string:gsplit(delimiter)
        delimiter = delimiter or ','          --default delimiter is comma
        if self:sub(-#delimiter) ~= delimiter then self = self .. delimiter end
        return self:gmatch('(.-)'..escape_magic(delimiter))
    end

    -- Split a string on the given delimiter (comma by default)
    function string:split(delimiter)
        local ans = {}
        for item in self:gsplit(delimiter) do
            ans[ #ans+1 ] = item
        end
        return ans
    end

    --gets a live reference to a record from its record ID
    local function getRecordFromId(id)
        if id == nil then return nil end
        local scriptRecord = nil
        local addressList = getAddressList()
        if addressList.Count >= 1 then
            scriptRecord = addressList.getMemoryRecordByID(id)
        end
        if scriptRecord ~= nil then
            scriptRecord.Type = 11 --11 is autoAssembler; not sure if this is necessary
        end
        return scriptRecord
    end

    local function removeFromAllLists(removalIndex)
        if removalIndex == nil then 
            print ("attempted to remove at a nil index")
            return nil
        end
        table.remove(pathList, removalIndex)
        table.remove(recordIdList, removalIndex)
        table.remove(recordList, removalIndex)
    end

    local function getStringFromMemoryStream(memoryStream)
        local fileStr = nil
        local stringStream = createStringStream()
        stringStream.Position = 0
        memoryStream.Position = 0
        stringStream.copyFrom(memoryStream, memoryStream.Size)
        fileStr = stringStream.DataString
        stringStream.destroy()
        return fileStr
    end

    local function getStringFromFile(path)
        local memoryStream = createMemoryStream()
        memoryStream.loadFromFile(path)
        if memoryStream == nil then
            ShowMessage("Path entered does not lead to a valid file.")
            return nil
        end
        local fileStr = getStringFromMemoryStream(memoryStream)
        return fileStr
    end

    --removes all data associated with a recordId, by deleting from the given recordId until a newline char
    local function removeDataFromSave(recordId)
        if recordId == nil then return nil end
        print("Removing record with ID: "..recordId)
        local tableFile = findTableFile(tableFileName)
        if tableFile == nil then return nil end
        local memoryStream = tableFile.getData()
        local fileStr = getStringFromMemoryStream(memoryStream) -- OPTIMIZATION OPPORTUNITY: - eliminate one stream copy operation
        local recordIdFileIndex, indexend = string.find(fileStr, tostring(recordId)) --find the recordId
        local newLineIndexStart, newlineIndexEnd = string.find(fileStr, "\n", indexend) -- search from the end of the recordId to find the first newline
        local strToCut = string.sub(fileStr, recordIdFileIndex, newlineIndexEnd)
        local newFileStr = string.gsub(fileStr, strToCut, "") --replace strToCut with emptiness in fileStr (delete strToCut)
        local byteTable = stringToByteTable(newFileStr)
        local newMemoryStream = createMemoryStream()
        newMemoryStream.Position = 0
        newMemoryStream.write(byteTable)
        tableFile.delete()          --delete table file and make a new one with the new string
        tableFile = createTableFile(tableFileName)
        memoryStream = tableFile.getData()
        memoryStream.Position = 0
        newMemoryStream.Position = 0
        memoryStream.copyFrom(newMemoryStream, newMemoryStream.Size)
        newMemoryStream.destroy()
    end

    local function addToAllLists(recordId, path)
        local record = getRecordFromId(recordId)
        if record == nil then print("record nil") return false end
        table.insert(pathList, path)
        table.insert(recordIdList, recordId)
        table.insert(recordList, record)
        local thisIndex = #pathList
        record.OnDestroy = function ()
            removeFromAllLists(thisIndex)
            removeDataFromSave(recordId)
            --if all records are removed, stop timer to save cpu time
            if SyncTimer ~= nil and recordIdList.Count == 0 then
                SyncTimer.setEnabled(false)
            end
        end
        return true
    end

    local function addDataToSave(recordId, path)
        local tableFile = findTableFile(tableFileName)
        if tableFile == nil then return nil end
        local memoryStream = tableFile.getData()
        memoryStream.Position = 0
        local tempStr = recordId.."»"..path..'\n'
        local byteTable = stringToByteTable(tempStr)
        memoryStream.write(byteTable)
    end

    local function timer_tick(timer)
        --Update all records in list with text from files in pathList
        for index, value in ipairs(recordIdList) do
            local fileString = getStringFromFile(pathList[index])
            local recordAtIndex = getRecordFromId(recordIdList[index])
            if recordAtIndex == nil then
                removeFromAllLists(index)
                removeDataFromSave(recordIdList[index])
            elseif fileString ~= nil and recordAtIndex.Type == 11 then
                recordAtIndex.Script = fileString
            end
        end
    end

    local function createMyTimer()
        --make a timer if it doesn't already exist
        if (SyncTimer == nil) then
            SyncTimer = createTimer(getMainForm())
            SyncTimer.Interval = timerInterval
            SyncTimer.OnTimer = timer_tick
            SyncTimer.setEnabled(true)
        end
    end

    local function saveData()
        local tableFile = findTableFile(tableFileName)
        if tableFile == nil then
            tableFile = createTableFile(tableFileName)
        end
        local memoryStream = tableFile.getData()
        memoryStream.Position = 0
        if pathList ~= nil and recordIdList ~= nil then
            for index, recordId in ipairs(recordIdList) do
                local tempStr = recordId.."»"..pathList[index]..'\n'
                local byteTable = stringToByteTable(tempStr)
                memoryStream.write(byteTable)
            end
        end
    end

    local function loadData()
        local tableFile = findTableFile(tableFileName)
        if tableFile == nil then return nil end
        print("loading data")
        createMyTimer() --ignore this
        local memoryStream = tableFile.getData()
        local fileStr = getStringFromMemoryStream(memoryStream)
        local lines = fileStr:split('\n')
        for index, line in ipairs(lines) do
            local lineSplit = line:split("»")
            local recordId = tonumber(lineSplit[1]) 
            if (getRecordFromId(recordId) == nil) then
                removeDataFromSave(recordId)
            else
                print("recordID loaded: "..recordId)
                local path = lineSplit[2]
                if (string.find(path, "\\\\") == nil) then
                    path = string.gsub(path, "\\", "\\\\")
                end
                addToAllLists(recordId, path)
                print("Path loaded: "..path)
            end
        end
    end

    local function setUpForm()
        local form = createForm(true)
        form.Caption = "Sync Scripts"
        form.Width = 600
        form.Height = 600
        --local topLeftMenu = createMainMenu(form)
        --local menuItem = topLeftMenu.getItems()
        --if menuItem == nil then print ("menuItem nil")
        --else menuItem.Caption = "Sync Scripts" end
        form.AllowDropFiles = true
        --fileNames is an array of file paths with single slashes. gsub adds extra slashes before passing to getStringFromFile
        form.OnDropFiles = function(sender, fileNames)
            if fileNames ~= nil then
                createMyTimer() -- function won't create if timer already exists
                for index, value in ipairs(fileNames) do
                    local extraSlashesPath = string.gsub(fileNames[index], "\\", "\\\\")
                    local addressList = getAddressList()
                    local record = addressList.createMemoryRecord()
                    record.Description = fileNames[index] -- maybe change this to be only what is after the last \
                    record.Type = 11 --11 is autoAssembler
                    if (addToAllLists(record.ID, extraSlashesPath) == false) then
                        print("failed to add") 
                    end
                    addDataToSave(record.ID, extraSlashesPath)
                end
                saveData()
                
            end
        end
        local label = createLabel(form)
        label.setTop(label.ClientWidth/2)
        label.Caption = "Enter Script Path"
        label.Width = 400
        label.Enabled = true
        label.Visible = true
        local editBox = createEdit(form) --editable box
        editBox.setTop(label.ClientWidth/2) -- x
        editBox.SetLeft(100) -- y
        editBox.SetWidth(100)
        --form.show() --should be done outside
        --form.bringToFront()
        return form
    end

    -- add item to enable sync to popup menu
    local popUpMenu = AddressList.PopupMenu
    local enableSyncMenuItem = createMenuItem(popUpMenu)
    enableSyncMenuItem.Caption = 'Enable Sync'
    enableSyncMenuItem.ImageIndex = MainForm.CreateGroup.ImageIndex
    popUpMenu.Items.insert(MainForm.CreateGroup.MenuIndex, enableSyncMenuItem)

    --add item to disable sync to popup menu
    local disableSyncMenuItem = createMenuItem(popUpMenu)
    disableSyncMenuItem.Caption = 'Disable Sync'
    disableSyncMenuItem.ImageIndex = MainForm.CreateGroup.ImageIndex
    popUpMenu.Items.insert(MainForm.CreateGroup.MenuIndex, disableSyncMenuItem)

    --add item to open sync form to popup menu
    local openSyncFormMenuItem = createMenuItem(popUpMenu)
    openSyncFormMenuItem.Caption = 'Sync Script'
    openSyncFormMenuItem.ImageIndex = MainForm.CreateGroup.ImageIndex
    popUpMenu.Items.insert(MainForm.CreateGroup.MenuIndex, openSyncFormMenuItem)

    local function loadEverything()
        loadData()
    end

    getMainForm().registerFirstShowCallback(loadEverything)

  
    enableSyncMenuItem.OnClick = function(s)
        local selectedRecord = AddressList.getSelectedRecord()

        -- ask for script path
        local scriptPath = InputQuery('Enter Script Path', 'Path to Script That Should be Synced', scriptPath)
        --this should really have better error checking...
        if scriptPath == nil then
            ShowMessage("Failed to sync script, you must enter a path!")
            return
        end
        local extraSlashesPath = string.gsub(scriptPath, "\\", "\\\\")
        addToAllLists(selectedRecord.ID, extraSlashesPath)
        addDataToSave(selectedRecord.ID, extraSlashesPath)
        
        createMyTimer()
    end

    disableSyncMenuItem.OnClick = function (s)
        local selectedRecord = AddressList.getSelectedRecord()

        --try to remove record from list of records to be updated
        local foundRecord = false
        for index, value in ipairs(recordIdList) do
            if recordIdList[index] == selectedRecord.ID then
                removeFromAllLists(index)
                removeDataFromSave(selectedRecord.ID)
                selectedRecord.OnDestroy = nil
                foundRecord = true
            end
        end
        if foundRecord == false then ShowMessage("Failed to find record in list of synced scripts, are you sure you clicked the right record?") end

        --if all records are removed, stop timer to save cpu time
        if SyncTimer ~= nil and recordIdList.Count == 0 then
            SyncTimer.setEnabled(false)
        end
        
    end

    openSyncFormMenuItem.OnClick = function (s)
        local form = setUpForm()
        if form == nil then ShowMessage("Failed to open form, please report this bug to the script's creator.") return end
        form.show()
        form.bringToFront()

    end
  
    return _m
end
  
require("ce.auto_sync")
