[ENABLE]
{$lua}
local filePath = "C:\\Users\\sands\\Desktop\\testStr.txt"
local tableScriptName = "Hellooo"

--Plan: get memory stream of .lua file written to by VSCode, then create a MemoryRecord
-- with createMemoryRecord() and set its Script property to the string contained in the
-- file memory stream

local function getLuaRecord(scriptName)
  local luaRecord = nil
  local addressList = getAddressList()
  if addressList.Count >= 1 then
    luaRecord = addressList.getMemoryRecordByDescription(scriptName)
  end
  if luaRecord == nil then
	  luaRecord = addressList.createMemoryRecord()
      luaRecord.Description = scriptName
  end
  luaRecord.Type = 11 --11 is autoAssembler
  return luaRecord
end

local function getStringFromFile(path)
  local memoryStream = createMemoryStream()
  memoryStream.loadFromFile(path)
  local fileStr = nil
  if memoryStream == nil then return nil end
  local stringStream = createStringStream()
  stringStream.Position = 0 -- if not set before using 'copyFrom' the 'StringStream' object will be inconsistent.
  stringStream.copyFrom(memoryStream, memoryStream.Size)
  fileStr = stringStream.DataString
  stringStream.destroy()
  return fileStr
end


local record = getLuaRecord(tableScriptName)
local fileString = getStringFromFile(filePath)
if record ~= nil and fileString ~= nil then
	record.Script = fileString
end

[DISABLE]
