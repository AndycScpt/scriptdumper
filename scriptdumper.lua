-- // Services & Globals
local ContentProvider = game:GetService("ContentProvider")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer

-- // Configuration
local Config = {
    -- Classes to be treated as scripts
    ScriptClasses = {"LocalScript", "ModuleScript", "Script"},
    -- Classes to be treated as remotes
    RemoteClasses = {"RemoteEvent", "RemoteFunction", "BindableEvent", "BindableFunction"},
    -- Service names to be preserved (others will be generic Folders)
    ServiceNames = {"StarterPlayerScripts", "StarterCharacterScripts"},
    -- XML character replacements
    Replacements = {["'"] = "&apos;", ["\""] = "&quot;", ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;"},
    -- Number of concurrent threads for decompilation
    DecompileThreads = 8,
    -- Timeout for each script decompilation (in seconds)
    DecompileTimeout = 30,
    -- Time in seconds to show the final completion message
    CompletionMessageDuration = 10,
    -- Instances/Services to completely ignore during the scan
    IgnoredInstances = {
        game:GetService("CoreGui"),
        game:GetService("CorePackages")
    }
}

-- // Main Logic
local startTime = tick()
local xmlLines = {'<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'}
local hierarchy = {["NIL_INSTANCES"] = {Class = "Folder", Children = {}}, ["LOADED_MODULES"] = {Class = "Folder", Children = {}}}
local scriptsToDecompile = {}
local seenInstanceIds = {}

--================------------------------------------------------------------------================--
--                                        USER INTERFACE
--================------------------------------------------------------------------================--

local UI = {}
do
    local viewportSize = workspace.CurrentCamera.ViewportSize
    local panelSize = Vector2.new(550, 80)
    local panelPosition = Vector2.new(viewportSize.X / 2 - panelSize.X / 2, viewportSize.Y - 120)

    -- Main Panel
    UI.Panel = Drawing.new("Square")
    UI.Panel.Color = Color3.new(0.1, 0.1, 0.1)
    UI.Panel.Transparency = 0.3
    UI.Panel.Filled = true
    UI.Panel.Size = panelSize
    UI.Panel.Position = panelPosition
    UI.Panel.Visible = true

    -- Title Text
    UI.Title = Drawing.new("Text")
    UI.Title.Text = "Roblox Script Saver"
    UI.Title.Color = Color3.new(1, 1, 1)
    UI.Title.Font = Drawing.Fonts.UI
    UI.Title.Size = 18
    UI.Title.Position = panelPosition + Vector2.new(10, 8)
    UI.Title.Visible = true

    -- Status Text
    UI.Status = Drawing.new("Text")
    UI.Status.Text = "Initializing..."
    UI.Status.Color = Color3.new(0.9, 0.9, 0.9)
    UI.Status.Font = Drawing.Fonts.UI
    UI.Status.Size = 16
    UI.Status.Position = panelPosition + Vector2.new(10, 30)
    UI.Status.Visible = true

    -- Progress Bar Background
    UI.ProgressBarBg = Drawing.new("Square")
    UI.ProgressBarBg.Color = Color3.new(0.2, 0.2, 0.2)
    UI.ProgressBarBg.Filled = true
    UI.ProgressBarBg.Size = Vector2.new(panelSize.X - 20, 10)
    UI.ProgressBarBg.Position = panelPosition + Vector2.new(10, panelSize.Y - 25)
    UI.ProgressBarBg.Visible = true

    -- Progress Bar Fill
    UI.ProgressBar = Drawing.new("Square")
    UI.ProgressBar.Color = Color3.fromRGB(70, 130, 255) -- A nice blue
    UI.ProgressBar.Filled = true
    UI.ProgressBar.Size = Vector2.new(0, UI.ProgressBarBg.Size.Y)
    UI.ProgressBar.Position = UI.ProgressBarBg.Position
    UI.ProgressBar.Visible = true

    function UI:SetStatus(text)
        self.Status.Text = tostring(text)
    end

    function UI:SetProgress(percentage) -- percentage is 0 to 1
        local newWidth = self.ProgressBarBg.Size.X * math.clamp(percentage, 0, 1)
        self.ProgressBar.Size = Vector2.new(newWidth, self.ProgressBar.Size.Y)
    end

    function UI:Cleanup()
        for _, element in pairs(self) do
            if typeof(element) == 'DrawingObject' then -- Fixed the typo here from your original script
                element:Remove()
            end
        end
    end
end

--================------------------------------------------------------------------================--
--                                        CORE FUNCTIONS
--================------------------------------------------------------------------================--

--- Checks if an instance is in the ignored list.
--- @param instance Instance The instance to check.
--- @return boolean True if the instance should be ignored.
local function isIgnored(instance)
    for _, ignoredParent in ipairs(Config.IgnoredInstances) do
        if instance == ignoredParent or instance:IsDescendantOf(ignoredParent) then
            return true
        end
    end
    return false
end

--- Traverses up the hierarchy to get all parents of an instance.
--- @param instance Instance The instance to trace.
--- @return table A list of parent instances.
local function getParentTree(instance)
    local tree = {}
    local current = instance.Parent
    while current and current ~= game do
        table.insert(tree, 1, current)
        current = current.Parent
    end
    return tree
end

--- Scans a list of instances and adds scripts/remotes to the hierarchy.
--- @param instanceList table The list of instances to scan.
--- @param isLoadedModule boolean True if scanning from getloadedmodules().
local function scanInstances(instanceList, isLoadedModule)
    for _, instance in ipairs(instanceList) do
        if typeof(instance) == "Instance" then
            -- Skip this instance if it's in an ignored path
            if isIgnored(instance) then continue end

            local isScript = table.find(Config.ScriptClasses, instance.ClassName)
            local isRemote = table.find(Config.RemoteClasses, instance.ClassName)

            if isScript or isRemote then
                local uniqueId = instance:GetDebugId()
                
                -- Add to loaded modules folder if it's a script and we are scanning loaded modules
                if isLoadedModule and isScript and not table.find(seenInstanceIds, uniqueId) then
                    hierarchy["LOADED_MODULES"].Children[uniqueId] = {Class = instance.ClassName, Ref = instance, Children = {}}
                end

                -- Add to main hierarchy if not already seen
                if not table.find(seenInstanceIds, uniqueId) then
                    table.insert(seenInstanceIds, uniqueId)

                    local parentTree = getParentTree(instance)
                    local currentHierarchy = hierarchy

                    if #parentTree == 0 and instance.Parent == nil then
                        -- This is a nil-parented instance
                        currentHierarchy = hierarchy["NIL_INSTANCES"].Children
                    else
                        -- Traverse or create the hierarchy path
                        for _, branch in ipairs(parentTree) do
                            local branchId = branch:GetDebugId()
                            if not currentHierarchy[branchId] then
                                local isService = game:FindService(branch.ClassName) or table.find(Config.ServiceNames, branch.ClassName)
                                currentHierarchy[branchId] = {Class = isService and branch.ClassName or "Folder", Ref = branch, Children = {}}
                            end
                            currentHierarchy = currentHierarchy[branchId].Children
                        end
                    end
                    
                    currentHierarchy[uniqueId] = {Class = instance.ClassName, Ref = instance, Children = {}}
                end
            end
        end
    end
end

--- Recursively builds the XML structure from the hierarchy table.
--- @param tree table The hierarchy tree to process.
local function buildXmlHierarchy(tree)
    for id, data in pairs(tree) do
        -- Create the XML item tag
        table.insert(xmlLines, '<Item class="' .. data.Class .. '" referent="RBX' .. #xmlLines .. '">')
        table.insert(xmlLines, '<Properties>')
        
        -- Set the name, sanitizing special characters
        local name = data.Ref and data.Ref.Name or id
        local sanitizedName = string.gsub(name, "['\"<>&]", Config.Replacements)
        table.insert(xmlLines, '<string name="Name">' .. sanitizedName .. '</string>')

        -- Handle script-specific properties and source
        if data.Ref and table.find(Config.ScriptClasses, data.Class) then
            if data.Class == "LocalScript" or data.Class == "Script" then
                table.insert(xmlLines, '<bool name="Disabled">' .. tostring(data.Ref.Disabled) .. '</bool>')
            end
            if data.Class == 'Script' then
                table.insert(xmlLines, '<token name="RunContext">' .. tostring(data.Ref.RunContext.Value) .. '</token>')
            end
            table.insert(xmlLines, '<ProtectedString name="Source"><![CDATA[')
            table.insert(xmlLines, "") -- Placeholder for decompiled source
            table.insert(xmlLines, ']]></ProtectedString>')
            
            -- Add to the list of scripts that need decompiling
            table.insert(scriptsToDecompile, {Script = data.Ref, Name = name, Index = #xmlLines - 1})
        end
        
        table.insert(xmlLines, "</Properties>")

        -- Recursively process children
        if next(data.Children) then
            buildXmlHierarchy(data.Children)
        end
        
        table.insert(xmlLines, "</Item>")
    end
end


--================------------------------------------------------------------------================--
--                                        EXECUTION FLOW
--================------------------------------------------------------------------================--

-- Step 1: Scan the game for all scripts and instances
UI:SetStatus("Phase 1/3: Scanning game for scripts...")
task.wait(1)
scanInstances(game:GetDescendants())
scanInstances(getnilinstances())
scanInstances(getloadedmodules(), true)
seenInstanceIds = nil -- Free up memory

-- Step 2: Build the XML file structure
UI:SetStatus("Phase 2/3: Building XML file structure...")
task.wait(1)
buildXmlHierarchy(hierarchy)
table.insert(xmlLines, "</roblox>")
local totalScriptCount = #scriptsToDecompile

-- Step 3: Decompile all found scripts using multiple threads
local doneScripts = 0
local runningThreads = Config.DecompileThreads
local scriptStatuses = {} -- Track status of each script
UI:SetStatus(string.format("Phase 3/3: Decompiling %d scripts...", totalScriptCount))
UI:SetProgress(0)

if totalScriptCount > 0 then
    for i = 1, Config.DecompileThreads do
        task.spawn(function()
            while #scriptsToDecompile > 0 do
                local job = table.remove(scriptsToDecompile, 1)
                if job then
                    local startTime = tick()
                    local timedOut = false
                    local decompileFinished = false
                    local decompileResult = nil
                    
                    -- Spawn decompile in a separate thread (fire and forget if it hangs)
                    task.spawn(function()
                        local success, output = pcall(decompile, job.Script)
                        if not decompileFinished and success and output and output ~= "" then
                            decompileResult = output
                        end
                        decompileFinished = true
                    end)
                    
                    -- Wait for completion or timeout (but DON'T wait for hung threads)
                    while not decompileFinished and (tick() - startTime) < Config.DecompileTimeout do
                        task.wait(0.05)
                    end
                    
                    -- Determine what happened
                    if decompileFinished and decompileResult then
                        -- Success - escape ]]> sequences that would break CDATA
                        local escapedSource = string.gsub(decompileResult, "]]>", "]]]]><![CDATA[>")
                        xmlLines[job.Index] = escapedSource
                        scriptStatuses[job.Name] = "success"
                    elseif not decompileFinished then
                        -- Timed out - abandon the thread and move on
                        xmlLines[job.Index] = "-- Decompilation timed out after " .. Config.DecompileTimeout .. " seconds."
                        scriptStatuses[job.Name] = "timeout"
                        timedOut = true
                    else
                        -- Failed or empty
                        xmlLines[job.Index] = "-- Failed to decompile script or script is empty."
                        scriptStatuses[job.Name] = "failed"
                    end
                    
                    -- Mark thread as done so we can move on
                    if timedOut then
                        decompileFinished = true -- Force abandonment
                    end
                    
                    doneScripts = doneScripts + 1
                    local progress = doneScripts / totalScriptCount
                    UI:SetProgress(progress)
                    UI:SetStatus(string.format("Phase 3/3: Decompiling... (%d / %d)", doneScripts, totalScriptCount))
                end
                task.wait()
            end
            runningThreads = runningThreads - 1
        end)
    end

    -- Wait for all decompile threads to finish
    while runningThreads > 0 do
        task.wait(0.1)
    end
else
    UI:SetStatus("Phase 3/3: No scripts found to decompile.")
    UI:SetProgress(1)
end


-- Step 4: Finalize and save the file
task.wait(1)
UI:SetProgress(1)

-- Safely get the game name
local gameName = "Unknown Game"
local success, productInfo = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
if success and productInfo then
    gameName = productInfo.Name
end

-- Sanitize filename
local sanitizedGameName = string.gsub(gameName, "[^%w%s_.-]", "")
local fileName = string.format("ScriptDump - %s - %d.rbxlx", sanitizedGameName, os.time())

-- Write file and show completion message
writefile(fileName, table.concat(xmlLines, "\n"))
local timeTaken = math.floor(tick() - startTime)
UI:SetStatus(string.format("Complete! Saved to %q in %d seconds.", fileName, timeTaken))

-- Cleanup UI after a delay
task.wait(Config.CompletionMessageDuration)
UI:Cleanup()