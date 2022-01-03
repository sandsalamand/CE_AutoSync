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

    --TODO: change function names to start with a capital
    local recordIdList = {}
    local recordList = {}
    local pathList = {}
    local tableFileName = "syncList.txt"
    local mainForm = nil
    local tableMainMenuItem = nil
    local SyncTimer = nil
    local listMenuItems = nil

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

    local function checkForTableMenuOpened()
        if(tableMainMenuItem.Count > 6) then
            return true
        end
        return false
    end

    --deletes the menuItem responsible for displaying the tableFile (only deletes the graphical representation of it, the tableFile itself is untouched)
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

    --Make a timer if it doesn't already exist
    local function createMyTimer()
        if (SyncTimer == nil) then
            SyncTimer = createTimer(mainForm)
            SyncTimer.Interval = timerInterval
            SyncTimer.OnTimer = timer_tick
            SyncTimer.setEnabled(true)
        end
    end

    --Loads data from table file into 3 lists (recordIdList, recordList, pathList)
    --RecordList is not filled from table, but recordIDs are used to find the record instances they're associated with
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
                    print("failed to add") 
                end
                addDataToSave(record.ID, extraSlashesPath)
            end
            saveDataToFile(tableFile) --honestly don't know why I'm saving it twice, will investigate
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

        local infoLabel = createLabel(form)
        infoLabel.Caption = "Add files by dropping them onto this window, or onto the main CE form."
        infoLabel.Font = infoFont
        infoLabel.Width = 400
        infoLabel.setTop(120)
        local xPosInfo = (form.Width/2) - (infoLabel.Width/2)
        infoLabel.setLeft(xPosInfo)
        infoLabel.Enabled = true
        infoLabel.Visible = true

        --create a listView with custom right-click behavior to allow deleting of files from sync list with context menu
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

    --Calls loadData to import data from the tableFile into our 3 lists
    --Sets up CE Main Menu "Sync Settings" menu item
    --Overloads funcs that call when record names are changed or files are dragged into CE
    local function loadEverything()
        local tableFile = findTableFile(tableFileName)
        if tableFile == nil then createTableFile(tableFileName) end
        loadData(tableFile)
        local mainMenuItems = mainForm.Menu.Items
        tableMainMenuItem = mainMenuItems[3]
        --replaces built-in name change InputQuery with our own so that we can pass the name to UpdateSyncListName
        AddressList.OnDescriptionChange = function(addresslist, memrec)
            local newName = InputQuery("Change Description", "What will be the new description?", memrec.Description)
            if newName ~= nil then
                memrec.Description = newName
                UpdateSyncListName(memrec, newName)
            end
            return true --tells AddressList that we don't want the default name change InputQuery to pop up
        end

        mainForm.OnDropFiles = function(sender, filenames) addFilesToSync(filenames) end
        createSyncSettingsMenuItem()
    end

    local popUpMenu = AddressList.PopupMenu
    --add item to disable sync to popup menu
    local disableSyncMenuItem = createMenuItem(popUpMenu)
    disableSyncMenuItem.Caption = 'Disable Sync'
    disableSyncMenuItem.ImageIndex = MainForm.CreateGroup.ImageIndex
    popUpMenu.Items.insert(MainForm.CreateGroup.MenuIndex, disableSyncMenuItem)
    disableSyncMenuItem.OnClick = function (s)
        local selectedRecord = AddressList.getSelectedRecord()
        disableSyncRecord(selectedRecord)
    end

    --add item to open sync form to popup menu
    local openSyncFormMenuItem = createMenuItem(popUpMenu)
    openSyncFormMenuItem.Caption = 'Sync Script'
    openSyncFormMenuItem.ImageIndex = MainForm.CreateGroup.ImageIndex
    popUpMenu.Items.insert(MainForm.CreateGroup.MenuIndex, openSyncFormMenuItem)
    openSyncFormMenuItem.OnClick = function (s)
        createAndShowSyncForm()
    end

    mainForm = getMainForm()
    mainForm.registerFirstShowCallback(loadEverything)
  
    return _m
end
  
require("ce.auto_sync")
