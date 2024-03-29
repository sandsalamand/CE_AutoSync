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
    local pollingInterval = 200
    ------------------------------------------------------------------------------------------

    local debugMode = false
    local recordIdList = {}
    local recordList = {}
    local pathList = {}
    local tableFileName = "Sync_Data_dont_delete.txt"
    local configFileName = "Sync_Config.txt"
    local mainForm = nil
    local SyncTimer = nil
    local listMenuItems = nil
    local overrideMainFormOnDrop = true

    local function debugLog(string)
        if (debugMode == true) then print(string) end
    end

    -- Escape special pattern characters in string to be treated as simple characters
    local function escape_magic(str)
        local MAGIC_CHARS_SET = '[()%%.[^$%]*+%-?]'
        if str == nil then return end
        return (str:gsub(MAGIC_CHARS_SET,'%%%1'))
    end

    -- Returns an iterator to split a string on the given delimiter (comma by default)
    function string:gsplit(delimiter)
        delimiter = delimiter or ','
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

    local function appendCheckMarkToRecord(record)
        local recordDescription = record.Description
        if (recordDescription:find("%✓") == nil) then
            debugLog("appending")
            record.Description = recordDescription.." ✓"
        end
    end

    local function appendWarningSignToRecord(record)
        local recordDescription = record.Description
        if (recordDescription:find("%🚫") == nil) then
            debugLog("appending")
            record.Description = recordDescription.." 🚫"
        end
    end

    local function removeCheckMarkFromRecord(record)
        record.Description = record.Description:gsub("%✓", "")
    end

    local function removeWarningSignFromRecord(record)
        record.Description = record.Description:gsub("%🚫", "")
    end

    local function boolToString(boolean)
        if boolean == true then return "true"
        else return "false" end
    end

    --Gets a live reference to a record from its record ID
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
            debugLog ("attempted to remove at a nil index")
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

    --Returns the raw text from a file
    local function getStringFromFile(path)
        local memoryStream = createMemoryStream()
        local loadSuccess = memoryStream.loadFromFileNoError(path)
        if loadSuccess == false then
            return nil end
        local fileStr = getStringFromMemoryStream(memoryStream)
        return fileStr
    end

    --Removes all data associated with a recordId by deleting from the index of the given recordId, up until a newline character
    local function removeDataFromSave(recordId)
        if recordId == nil then return nil end
        debugLog("Removing record with ID: "..recordId)
        local tableFile = findTableFile(tableFileName)
        if tableFile == nil then return nil end
        local memoryStream = tableFile.getData()
        local fileStr = getStringFromMemoryStream(memoryStream) -- OPTIMIZATION OPPORTUNITY: - eliminate one stream copy operation
        local recordIdFileIndex, indexend = fileStr:find(tostring(recordId)) --find the recordId
        local newLineIndexStart, newlineIndexEnd = fileStr:find("\n", indexend) -- search from the end of the recordId to find the first newline
        local strToCut = fileStr:sub(recordIdFileIndex, newlineIndexEnd)
        local newFileStr = fileStr:gsub(strToCut, "") --replace strToCut with emptiness in fileStr (delete strToCut)
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
        if record == nil then debugLog("record nil") return false end
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

    local function setupNewConfigFile(fileName)
        local existingTableFile = findTableFile(fileName)
        if existingTableFile ~= nil then existingTableFile:destroy() end
        local returnTableFile = createTableFile(fileName)
        local memoryStream = returnTableFile.getData()
        local tempStr
        if overrideMainFormOnDrop == true then tempStr = "true\n"
        else tempStr = "false\n" end
        local byteTable = stringToByteTable(tempStr)
        memoryStream.write(byteTable)
        return returnTableFile
    end

    local function clearAndWriteToConfigFile(fileName, strToWrite)
        local tableFile = findTableFile(fileName)
        if tableFile == nil then return nil end
        local memoryStream = tableFile.getData()
        local byteTable = stringToByteTable(strToWrite .. "  ") --add a couple spaces at the end
        memoryStream.write(byteTable)
    end

    local function parseConfigFile(configTableFile)
        if configTableFile == nil then
            return true, setupNewConfigFile(configFileName) -- if config file is missing, then return a fresh one
        end
        local memoryStream = configTableFile.getData()
        local fileStr = getStringFromMemoryStream(memoryStream)
        local falseStrIndex = fileStr:find("false")
        local trueStrIndex = fileStr:find("true")

        --switch based on true/false strings in config file
        if (falseStrIndex == nil and trueStrIndex == nil) or (falseStrIndex ~= nil and trueStrIndex ~= nil) then
            configTableFile:delete()
            debugLog ("file was bad")
            return true, setupNewConfigFile(configFileName) -- if config file is broken, then return a fresh one
        elseif (falseStrIndex ~= nil) then
            return false, configTableFile
        else
            return true, configTableFile
        end
    end

    local function timer_tick(timer)
        local syncDataFile = findTableFile(tableFileName)
        if syncDataFile == nil then
            createTableFile(tableFileName)
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

        --check config file
        local configFile = findTableFile(configFileName)
        overrideMainFormOnDrop, configFile = parseConfigFile(configFile)
    end

    --Make a timer if it doesn't already exist
    local function createMyTimer()
        if (SyncTimer == nil) then
            SyncTimer = createTimer(mainForm)
            SyncTimer.Interval = pollingInterval
            SyncTimer.OnTimer = timer_tick
            SyncTimer.setEnabled(true)
        end
    end

    --Loads data from table file into 3 lists (recordIdList, recordList, pathList)
    --RecordList is not filled from table, but recordIDs are used to find the record instances they're associated with
    local function loadData(tableFile)
        if tableFile == nil then return nil end
        debugLog("loading data")
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
                debugLog("recordID loaded: "..recordId)
                local path = lineSplit[2]
                if (path:find("\\\\") == nil) then
                    path = path:gsub("\\", "\\\\")
                end
                addToAllLists(recordId, path)
                debugLog("Path loaded: "..path)
            end
        end
    end

    local function getFileNameFromPath(path)
        local lastdotpos = (path:reverse()):find("\\")
        return (path:sub(1 - lastdotpos))
    end

    --Creates new memory records for files
    --Adds their paths to pathList
    --Adds their new recordID and record instance to recordIdList and recordList
    --Saves data to tableFile
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
                    debugLog("failed to add") 
                end
                addDataToSave(record.ID, extraSlashesPath)
            end
            saveDataToFile(tableFile) --not sure why I save again at the end
        end
    end

    -- Removes recordId, path, and instance pointer associated with a record from the 3 lists
    local function disableSyncRecord(record)
        if record == nil then return nil end
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

    --Sets up a form with 2 labels and a list view
    --Form has custom behavior for files dropped onto it, and for closing
    local function setUpForm()
        local form = createForm(true)
        form.Caption = "Sync Scripts"
        form.Width = 900
        form.Height = 1200
        form.AllowDropFiles = true
        form.OnDropFiles = function(sender, fileNames) addFilesToSync(fileNames) end
        form.OnClose = function (s)
            listMenuItems = nil
            form.Enabled = false
            form.hide()
        end

        local titleFont = createFont()
        titleFont.Size = 24
        titleFont.Style = 'fsBold'
        local infoFont = createFont()
        infoFont.Size = 11
        infoFont.Style = 'fsItalic'
        local rowItemFont = createFont()
        rowItemFont.Size = 10

        local titleLabel = createLabel(form)
        titleLabel.Caption = "List of Auto-Synced Files"
        titleLabel.Font = titleFont
        titleLabel.Width = 400
        titleLabel.setTop(20)
        local xPosTitle = (form.Width/2) - (titleLabel.Width/2)
        titleLabel.setLeft(xPosTitle)
        titleLabel.Enabled = true
        titleLabel.Visible = true

        local mainFormOnDropCheckBox = createCheckBox(form)
        mainFormOnDropCheckBox.Caption = "Allow Dragging Files onto Main Form"
        mainFormOnDropCheckBox.Font = rowItemFont
        mainFormOnDropCheckBox.Width = 400
        mainFormOnDropCheckBox.setTop(1110)
        local xPosCheckBox = (form.Width/2) - (mainFormOnDropCheckBox.Width/2)
        mainFormOnDropCheckBox.setLeft(xPosCheckBox)
        --set global boolean to checkbox state
        debugLog (boolToString(overrideMainFormOnDrop))
        mainFormOnDropCheckBox.Checked = overrideMainFormOnDrop
        mainFormOnDropCheckBox.OnChange = function(sender)
            overrideMainFormOnDrop = mainFormOnDropCheckBox.Checked
            clearAndWriteToConfigFile(configFileName, boolToString(overrideMainFormOnDrop))
            debugLog (boolToString(overrideMainFormOnDrop))
        end
        mainFormOnDropCheckBox.Enabled = true
        mainFormOnDropCheckBox.Visible = true

        local infoLabel = createLabel(form)
        infoLabel.Caption = "Add files by dropping them onto this window, or onto the main CE form."
        infoLabel.Font = infoFont
        infoLabel.Width = 400
        infoLabel.setTop(115)
        local xPosInfo = (form.Width/2) - (infoLabel.Width/2)
        infoLabel.setLeft(xPosInfo)
        infoLabel.Enabled = true
        infoLabel.Visible = true

        --create a listView with custom right-click behavior to allow deleting of files from sync list with context menu
        local listView = createListView(form)
        listView.Width = 800
        listView.Height = 870
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
        stopSyncMenuItem.OnClick = function(sender)
            local selectedItem = listView.Selected
            if selectedItem == nil then return nil end
            disableSyncRecord(recordList[selectedItem.Index + 1])
        end

        --create two columns, then fill them with record names and paths
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
        --populate listView with row entries
        for index, record in ipairs(recordList) do
            local recordDescriptionItem = listMenuItems.add()
            recordDescriptionItem.Caption = record.Description:gsub("%✓", "") --remove checkmarks for sync list display
            recordDescriptionItem.SubItems.add(pathList[index])     --SubItems refers to the second column of a row
        end
        listView.Enabled = true
        listView.Visible = true
        return form
    end

    local function createAndShowSyncForm()
        --TODO: check if form already exists before creating
        local form = setUpForm()
        if form == nil then ShowMessage("Failed to open form, please report this bug to the script's creator.") return end
        form.show()
        form.bringToFront()
    end

    --Creates a new menu item in the CE Main Menu (top left bar of CE) under Settings
    local function createSyncSettingsMenuItem()
        local mainMenuItems = mainForm.Menu.Items
        local settingsMainMenuItem = mainMenuItems[1]
        local syncMenuItem = createMenuItem(mainForm.Menu)
        syncMenuItem.Caption = "Sync Settings"
        syncMenuItem.Parent = settingsMainMenuItem
        syncMenuItem.OnClick = createAndShowSyncForm
        settingsMainMenuItem:add(syncMenuItem)
    end

    --Updates a row Caption in the listView of the sync list form
    local function updateSyncListName (memrec, newName)
        if listMenuItems == nil then return nil end
        debugLog ("updating name")
        for index, record in ipairs(recordList) do
            if record == memrec then
                local item = listMenuItems.getItem(index - 1)
                item.Caption = newName:gsub("%✓", "")
            end
        end
    end

    local function mainFormFilesDropped(filenames)
        debugLog(boolToString(overrideMainFormOnDrop))
        if overrideMainFormOnDrop == true then
            addFilesToSync(filenames)
        end
    end

    --Set up from config file
    --Import data from the tableFile into our 3 lists
    --Overload funcs that call when record names are changed or files are dragged into CE
    local function loadEverything()
        --check config file and set overrideMainFormOnDrop boolean
        local configFile = findTableFile(configFileName)
        overrideMainFormOnDrop, configFile = parseConfigFile(configFile)

        --import data from sync data file, or create a new one if it doesn't exist
        local syncDataFile = findTableFile(tableFileName)
        if syncDataFile == nil then
            syncDataFile =  createTableFile(tableFileName)
        end
        loadData(syncDataFile)

        --replaces built-in name change InputQuery with our own so that we can pass the name to UpdateSyncListName
        AddressList.OnDescriptionChange = function(addresslist, memrec)
            local newName = InputQuery("Change Description", "What will be the new description?", memrec.Description)
            if newName ~= nil then
                memrec.Description = newName
                updateSyncListName(memrec, newName)
            end
            return true --tells AddressList that we don't want the default name change InputQuery to pop up
        end

        mainForm.OnDropFiles = function(sender, filenames) mainFormFilesDropped(filenames) end

        createSyncSettingsMenuItem()
    end

    local function addContextMenuItem(itemName, onClickFunction)
        local popUpMenu = AddressList.PopupMenu
        --add item to disable sync to popup menu
        local disableSyncMenuItem = createMenuItem(popUpMenu)
        disableSyncMenuItem.Caption = itemName
        disableSyncMenuItem.ImageIndex = MainForm.CreateGroup.ImageIndex
        popUpMenu.Items.insert(MainForm.CreateGroup.MenuIndex, disableSyncMenuItem)
        disableSyncMenuItem.OnClick = onClickFunction
    end

    --add disableSync item to context menu
    addContextMenuItem('Disable Sync', function (s)
        local selectedRecords = AddressList.getSelectedRecords()
        for index, record in pairs(selectedRecords) do
            disableSyncRecord(record)
        end
    end)

    mainForm = getMainForm()
    mainForm.registerFirstShowCallback(loadEverything)
  
    return _m
end
  
require("ce.auto_sync")
