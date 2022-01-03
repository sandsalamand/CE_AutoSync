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
    local mainForm = nil
    local tableMainMenuItem = nil
    local SyncTimer = nil
    local listMenuItems = nil

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
        local loadSuccess = memoryStream.loadFromFileNoError(path)
        if loadSuccess == false then
            return nil end
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
        if listMenuItems ~= nil then
            local recordDescriptionItem = listMenuItems.add()
            recordDescriptionItem.Caption = record.Description
            recordDescriptionItem.SubItems.add(pathList[thisIndex])
        end
        record.OnDestroy = function ()
            removeFromAllLists(thisIndex)
            removeDataFromSave(recordId)
            if listMenuItems ~= nil then
                local item = listMenuItems.getItem(thisIndex - 1)
                item:delete()
            end
            --if all records are removed, stop timer to save cpu time
            if SyncTimer ~= nil and recordIdList.Count == 0 then
                SyncTimer.setEnabled(false)
            end
        end
        return true
    end

    local function addDataToSave(recordId, path)
        local tableFile = findTableFile(tableFileName)
        local memoryStream = tableFile.getData()
        memoryStream.Position = 0
        local tempStr = recordId.."»"..path..'\n'
        local byteTable = stringToByteTable(tempStr)
        memoryStream.write(byteTable)
    end

    --should condense these 4 functions into 2
    local function appendCheckMarkToRecord(record)
        local recordDescription = record.Description
        if (recordDescription:find("%✓") == nil) then
            print("appending")
            record.Description = recordDescription.." ✓"
        end
    end

    local function appendWarningSignToRecord(record)
        local recordDescription = record.Description
        if (recordDescription:find("%🚫") == nil) then
            print("appending")
            record.Description = recordDescription.." 🚫"
        end
    end

    local function removeCheckMarkFromRecord(record)
        record.Description = record.Description:gsub("%✓", "")
    end

    local function removeWarningSignFromRecord(record)
        record.Description = record.Description:gsub("%🚫", "")
    end
    ----

    local function saveDataToFile(tableFile)
        if tableFile == nil then return nil end
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

    local function createTableFileWithData(name)
        local tableFile = createTableFile(name)
        saveDataToFile(tableFile)
        return tableFile
    end

    local function checkForTableMenuOpened()
        if(tableMainMenuItem.Count > 6) then
            return true
        end
        return false
    end

    local function deleteSyncListMenuItem()
        local itemCaption
        local i = 0
        local menuItemCount = tableMainMenuItem.Count
        while(i < menuItemCount) do
            itemCaption = tableMainMenuItem.Item[i].Caption
            if (itemCaption == tableFileName) then
                tableMainMenuItem.delete(i)
            end
            i = i + 1
        end
        return nil
    end

    local function timer_tick(timer)
        --if user opens the Table MenuItem, delete syncList menuItem to prevent them from deleting it
        if(checkForTableMenuOpened() == true) then --triggers when menu is open
            deleteSyncListMenuItem()                                                              --RE-ENABLE THIS WHEN DONE DEBUGGING
        end
        --Update all records in list with text from files in pathList
        for index, recordId in ipairs(recordIdList) do
            local fileString = getStringFromFile(pathList[index])
            local recordAtIndex = getRecordFromId(recordId)
            if fileString == nil then
                removeCheckMarkFromRecord(recordAtIndex)
                appendWarningSignToRecord(recordAtIndex)
            end
            if recordAtIndex == nil then
                removeFromAllLists(index)
                removeDataFromSave(recordId)
            elseif fileString ~= nil and recordAtIndex.Type == 11 then
                recordAtIndex.Script = fileString
                appendCheckMarkToRecord(recordAtIndex)
            end
        end
    end

    local function createMyTimer()
        --make a timer if it doesn't already exist
        if (SyncTimer == nil) then
            SyncTimer = createTimer(mainForm)
            SyncTimer.Interval = timerInterval
            SyncTimer.OnTimer = timer_tick
            SyncTimer.setEnabled(true)
        end
    end

    local function loadData(tableFile)
        if tableFile == nil then return nil end
        print("loading data")
        createMyTimer()
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

    local function getFileNameFromPath(path)
        local lastdotpos = (path:reverse()):find("\\")
        return (path:sub(1 - lastdotpos))
    end

    local function addFilesToSync(paths)
        local tableFile = findTableFile(tableFileName)
        if paths ~= nil and tableFile ~= nil then
            createMyTimer() -- function won't create if timer already exists
            for index, path in ipairs(paths) do
                local addressList = getAddressList()
                local record = addressList.createMemoryRecord()
                record.Description = getFileNameFromPath(path)
                record.Type = 11 --11 is autoAssembler
                local extraSlashesPath = string.gsub(path, "\\", "\\\\")
                if (addToAllLists(record.ID, extraSlashesPath) == false) then
                    print("failed to add") 
                end
                addDataToSave(record.ID, extraSlashesPath)
            end
            saveDataToFile(tableFile)
        end
    end

    local function disableSyncRecord(record)
        if record == nil then return nil end
        --try to remove record from list of records to be updated
        local foundRecord = false
        for index, value in ipairs(recordIdList) do
            if recordIdList[index] == record.ID then
                removeFromAllLists(index)
                removeDataFromSave(record.ID)
                removeCheckMarkFromRecord(record)
                removeWarningSignFromRecord(record)
                if listMenuItems ~= nil then
                    local item = listMenuItems.getItem(index - 1)
                    item:delete()
                end
                record.OnDestroy = nil
                foundRecord = true
            end
        end
        if foundRecord == false then ShowMessage("Failed to find record in list of synced scripts, are you sure you clicked the right record?") end

        --if all records are removed, stop timer to save cpu time
        if SyncTimer ~= nil and recordIdList.Count == 0 then
            SyncTimer.setEnabled(false)
        end
    end

    local function setListMenuItemsNil()
        listMenuItems = nil
    end

    local function setUpForm()
        local form = createForm(true)
        form.Caption = "Sync Scripts"
        form.Width = 900
        form.Height = 1200
        form.AllowDropFiles = true
        --fileNames is an array of file paths with single slashes. gsub adds extra slashes before passing to getStringFromFile
        form.OnDropFiles = function(sender, fileNames) addFilesToSync(fileNames) end
        form.OnClose = function (s)
            listMenuItems = nil
            form.Enabled = false
            form.hide()
        end

        local titleFont = createFont()
        titleFont.Size = 24
        titleFont.Style = 'fsBold'

        local titleLabel = createLabel(form)
        titleLabel.Caption = "List of Auto-Synced Files"
        titleLabel.Font = titleFont
        titleLabel.Width = 400
        titleLabel.setTop(20)
        local xPosTitle = (form.Width/2) - (titleLabel.Width/2)
        titleLabel.setLeft(xPosTitle)
        titleLabel.Enabled = true
        titleLabel.Visible = true

        local infoFont = createFont()
        infoFont.Size = 11
        infoFont.Style = 'fsItalic'

        local infoLabel = createLabel(form)
        infoLabel.Caption = "Add files by dropping them onto this window, or onto the main CE form."
        infoLabel.Font = infoFont
        infoLabel.Width = 400
        infoLabel.setTop(120)
        local xPosInfo = (form.Width/2) - (infoLabel.Width/2)
        infoLabel.setLeft(xPosInfo)
        infoLabel.Enabled = true
        infoLabel.Visible = true

        local rowItemFont = createFont()
        rowItemFont.Size = 10

        local listView = createListView(form)
        listView.Width = 800
        listView.Height = 800
        listView.setTop(200)
        local xPosListView = (form.Width/2) - (listView.Width/2)
        listView.setLeft(xPosListView)
        listView.ReadOnly = true
        listView.RowSelect = true
        listView.Font = rowItemFont
        local lvPopupMenu = createPopupMenu(listView)
        listView.setPopupMenu(lvPopupMenu)
        local stopSyncMenuItem = createMenuItem(lvPopupMenu)
        stopSyncMenuItem.Caption = 'Remove from Sync List'
        stopSyncMenuItem.ImageIndex = MainForm.CreateGroup.ImageIndex --change this
        lvPopupMenu.Items.insert(0, stopSyncMenuItem)
        stopSyncMenuItem.OnClick = function(s)
            local selectedItem = listView.Selected
            if selectedItem == nil then return nil end
            disableSyncRecord(recordList[selectedItem.Index + 1])
        end

        listMenuItems = listView.Items  --global
        local listColumns = listView.Columns
        local recordNameColumn = listColumns.add()
        recordNameColumn.Caption = "Record Name"
        recordNameColumn.Width = listView.width/2
        recordNameColumn.Visible = true
        local pathColumn = listColumns.add()
        pathColumn.Caption = "Path"
        pathColumn.Width = listView.width/2
        pathColumn.Visible = true
        for index, record in ipairs(recordList) do
            local recordDescriptionItem = listMenuItems.add()
            recordDescriptionItem.Caption = record.Description:gsub("%✓", "") --remove checkmarks for sync list display
            recordDescriptionItem.SubItems.add(pathList[index])
        end
        --print(listItems.Count)
        --syncListLabel.Font = infoFont
        listView.Enabled = true
        listView.Visible = true

        return form
    end

    local function createAndShowSyncForm()
        --TODO: see if it's possible to check if form already exists before creating
        local form = setUpForm()
        if form == nil then ShowMessage("Failed to open form, please report this bug to the script's creator.") return end
        form.show()
        form.bringToFront()
    end

    local popUpMenu = AddressList.PopupMenu
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

    local function createSyncSettingsMenuItem()
        local mainMenuItems = mainForm.Menu.Items
        local settingsMainMenuItem = mainMenuItems[1]
        local syncMenuItem = createMenuItem(mainForm.Menu)
        syncMenuItem.Caption = "Sync Settings"
        syncMenuItem.Parent = settingsMainMenuItem
        syncMenuItem.OnClick = createAndShowSyncForm
        settingsMainMenuItem:add(syncMenuItem)
    end

    local function UpdateSyncListName (memrec, newName)
        if listMenuItems == nil then return nil end
        print ("updating name")
        for index, record in ipairs(recordList) do
            if record == memrec then
                local item = listMenuItems.getItem(index - 1)
                item.Caption = newName:gsub("%✓", "")
            end
        end
    end

    local function loadEverything()
        local tableFile = findTableFile(tableFileName)
        if tableFile == nil then createTableFile(tableFileName) end
        loadData(tableFile)
        local mainMenuItems = mainForm.Menu.Items
        tableMainMenuItem = mainMenuItems[3]
        AddressList.OnDescriptionChange = function(addresslist, memrec)
            local newName = InputQuery("Change Description", "What will be the new description?", memrec.Description)
            if newName ~= nil then
                memrec.Description = newName
                UpdateSyncListName(memrec, newName)
            end
            return true
        end

        mainForm.OnDropFiles = function(sender, filenames) addFilesToSync(filenames) end
        createSyncSettingsMenuItem()
    end

    mainForm = getMainForm()
    mainForm.registerFirstShowCallback(loadEverything)

    disableSyncMenuItem.OnClick = function (s)
        local selectedRecord = AddressList.getSelectedRecord()
        disableSyncRecord(selectedRecord)
    end

    openSyncFormMenuItem.OnClick = function (s)
        createAndShowSyncForm()
    end
  
    return _m
end
  
require("ce.auto_sync")
