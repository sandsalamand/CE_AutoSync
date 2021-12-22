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
    --Path must have \\ for each \
    local defaultPath = "C:\\Users\\sands\\Documents\\VSCode_BulletBitmap\\BitmapToBullet.lua"
    local tableScriptName = "Synchronization Test"
    local timerInterval = 300
    ------------------------------------------------------------------------------------------

    --TODO: try changing function names to start with a capital
    --I really should have used a dictionary instead of two tables
    local recordIdList = {}
    local pathList = {}
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

    local function getRecordFromId(id)
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
    
    local function getStringFromMemoryStream(memoryStream)
        local fileStr = nil
        local stringStream = createStringStream()
        stringStream.Position = 0
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

    local function timer_tick(timer)
        --Update all records in list with text from files in pathList
        for index, value in ipairs(recordIdList) do
            local fileString = getStringFromFile(pathList[index])
            local recordAtIndex = getRecordFromId(recordIdList[index])
            if recordAtIndex == nil then
                table.remove(recordIdList, index) --remove record ID from list if reference is nil
                table.remove(pathList, index)
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
        local tableFileName = "syncList"
        local tableFile = findTableFile(tableFileName)
        if tableFile == nil then
            tableFile = createTableFile(tableFileName)
        end
        local memoryStream = tableFile.getData()
        --local byteTable = stringToByteTable("byteTable test") -- Use this method, it formats it better in the file
        --memoryStream.write(byteTable)
        if pathList ~= nil and recordIdList ~= nil then
            for index, recordId in ipairs(recordIdList) do
                local tempStr = recordId.."»"..pathList[index]..'\n'
                local byteTable = stringToByteTable(tempStr)
                memoryStream.write(byteTable)
            end
        end
    end

    local function readData()
        local tableFileName = "syncList"
        local tableFile = findTableFile(tableFileName)
        if tableFile == nil then return nil end
        local memoryStream = tableFileName.getData()
        local fileStr = getStringFromMemoryStream(memoryStream)

        local dataPresent = true
        while (dataPresent == true) do
            local lines = fileStr.split('\n')
            for index, val in ipairs(lines) do
                
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
                createMyTimer()
                for index, value in ipairs(fileNames) do
                    --print(fileNames[index])
                    local extraSlashesPath = string.gsub(fileNames[index], "\\", "\\\\")
                    table.insert(pathList, extraSlashesPath)
                    local addressList = getAddressList()
                    local record = addressList.createMemoryRecord()
                    record.Description = fileNames[index] -- maybe change this to be only what is after the last \
                    record.Type = 11 --11 is autoAssembler
                    table.insert(recordIdList, record.Id)
                end
                saveData()
                
            end
        end
        local label = createLabel(form)
        label.Caption = "Enter Script Path"
        label.Width = 200
        label.Enabled = true
        label.Visible = true
        local editBox = createEdit(form) --editable box
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


    readData()

  
    enableSyncMenuItem.OnClick = function(s)
        local selectedRecord = AddressList.getSelectedRecord()

        -- ask for script path
        local scriptPath = InputQuery('Enter Script Path', 'Path to Script That Should be Synced', scriptPath)
        --this should really have better error checking...
        if scriptPath == nil then
            ShowMessage("Failed to sync script, you must enter a path!")
            return
        end
        table.insert(pathList, scriptPath)
        table.insert(recordIdList, selectedRecord.Id)
        
        createTimer()
    end

    disableSyncMenuItem.OnClick = function (s)
        local selectedRecord = AddressList.getSelectedRecord()

        --try to remove record from list of records to be updated
        local foundRecord = false
        for index, value in ipairs(recordIdList) do
            if recordIdList[index] == selectedRecord.Id then
                table.remove(recordIdList, index)
                table.remove(pathList, index)
                foundRecord = true
            end
        end
        if foundRecord == false then ShowMessage("Failed to find record in list of synced scripts, are you sure you clicked the right record?") end

        --if all records are removed, stop timer to save cpu time
        if SomeTimer ~= nil and recordIdList.Count == 0 then
            SomeTimer.setEnabled(false)
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
