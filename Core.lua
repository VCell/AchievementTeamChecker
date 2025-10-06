-- AchievementTeamChecker
local ATC = {
    achievementButtons = {},
    eventFrame = nil,
    isHooked = false,
    currentQuery = nil,
    debug = false,
    MESSAGE_DELAY = 0.5
}

-- 初始化
function ATC:Init()
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("PLAYER_LOGIN")
    self.eventFrame:SetScript("OnEvent", function(_, event, ...)
        self[event](self, ...)
    end)
end

-- 初始化
function ATC:SetDebug(debug)
    self.debug = debug
end

-- 玩家登录后开始尝试Hook成就界面
function ATC:PLAYER_LOGIN()
    self:HookAchievementUI()
    
    -- -- 定期检查成就界面是否加载
    -- C_Timer.NewTicker(5, function()
    --     if not self.isHooked and AchievementFrame and AchievementFrame:IsShown() then
    --         self:HookAchievementUI()
    --     end
    -- end)
end

-- Hook 成就界面
function ATC:HookAchievementUI()
    if self.isHooked or not AchievementFrame then
        return
    end
    
    -- 方法1: 直接Hook成就按钮显示函数
    if AchievementButton_DisplayAchievement then
        hooksecurefunc("AchievementButton_DisplayAchievement", function(button, category, achievement)
            self:AddQueryButtonToAchievement(button, category, achievement)
        end)
        self.isHooked = true
        self:Print("成就团队检查插件已加载")
        return
    end
    
    -- 方法2: 监听成就框架显示事件
    self.eventFrame:RegisterEvent("ACHIEVEMENT_EARNED")
    self.eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "ACHIEVEMENT_EARNED" then
            if AchievementFrame and AchievementFrame:IsVisible() then
                self:DelayHook()
            end
        elseif event == "INSPECT_ACHIEVEMENT_READY" then
            self:INSPECT_ACHIEVEMENT_READY(...)
        end
    end)
end

-- 延迟Hook以确保界面完全加载
function ATC:DelayHook()
    C_Timer.After(0.5, function()
        if not self.isHooked and AchievementButton_DisplayAchievement then
            hooksecurefunc("AchievementButton_DisplayAchievement", function(button, category, achievement)
                ATC:AddQueryButtonToAchievement(button, category, achievement)
            end)
            self.isHooked = true
            self:Print("成就团队检查插件已加载")
        end
    end)
end

-- 添加查询按钮到成就
function ATC:AddQueryButtonToAchievement(button, category, achievement)
    if not button or not achievement or self.isHooked == false then return end
    

    local id, name, _, _, _, _, _, description, _, icon = GetAchievementInfo(category, achievement)
    button.description:SetText(description..' ID: '..id)

    if not id then return end
    
    -- 创建查询按钮
    local queryButton = button.queryButton
    if not queryButton then
        queryButton = CreateFrame("Button", nil, button, "UIPanelButtonTemplate")
        queryButton:SetSize(80, 22)
        queryButton:SetText("团队查询")
        queryButton:SetPoint("TOPRIGHT", button, "TOPRIGHT", -5, -5)
        queryButton:SetFrameLevel(button:GetFrameLevel() + 1)
        
        -- 悬停提示
        queryButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("查询团队成就完成情况")
            GameTooltip:AddLine("点击在团队频道公布结果", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        
        queryButton:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        
        button.queryButton = queryButton
    end
    queryButton:SetScript("OnClick", function()
        ATC:QueryTeamAchievement(id, name)
    end)
    queryButton:Show()
end

-- 注册成就检查事件
function ATC:RegisterAchievementEvents()
    self.eventFrame:RegisterEvent("INSPECT_ACHIEVEMENT_READY")
end

-- 成就数据就绪事件
function ATC:INSPECT_ACHIEVEMENT_READY(guid)
    ATC:Debug("INSPECT_ACHIEVEMENT_READY ".. guid)
    if not self.currentQuery then return end

    local query = self.currentQuery
    local unit = query.currentUnit
    
    if unit and guid == UnitGUID(unit) then
        -- 取消当前单位的超时计时器
        if query.currentTimeout then
            query.currentTimeout:Cancel()
            query.currentTimeout = nil
        end

        local name = GetUnitName(unit, true)

        ATC:Debug("INSPECT_ACHIEVEMENT_READY GetAchievementComparisonInfo")
        local isCompleted, _, _, _  = GetAchievementComparisonInfo(query.currentAchievementID)
        ATC:Debug(string.format("GetAchievementComparisonInfo unit:%s, name:%s id:%d result:%s", unit, name,
            query.currentAchievementID, tostring(isCompleted)))

        if not isCompleted then
            query:AddMissingPlayer(name)
        else
            query:AddCompletePlayer(name)
        end
        
        query.currentUnit = nil
        self:StartNextQuery()
    else
        ATC:Debug("INSPECT_ACHIEVEMENT_READY ERROR GUID:".. guid)
    end

end

-- 查询团队成就
function ATC:QueryTeamAchievement(achievementID, achievementName)
    if not IsInGroup() and not IsInRaid() then
        self:Debug("成就团队检查: 你不在团队中！")
        return
    end
    if self.currentQuery ~= nil then
        self:Debug(string.format("当前成就 %s[%d] 检查中，稍后重试", 
            self.currentQuery.currentAchievementName, self.currentQuery.currentAchievementID))
    end

    ATC:Debug(string.format("QueryTeamAchievement %s[%d]", achievementName, achievementID))
    -- 重置状态

    self:RegisterAchievementEvents()
    
    local unitPrefix = IsInRaid() and "raid" or "party"
    local numGroupMembers = GetNumGroupMembers()
    
    self.currentQuery = ATC:CreateQueryState(achievementID, achievementName)
    local query = self.currentQuery
    query.totalMembers = numGroupMembers
    
    -- 检查自己

    local selfCompleted = select(13, GetAchievementInfo(achievementID))

    if not selfCompleted then
        query:AddMissingPlayer(GetUnitName("player", true))
    else
        query:AddCompletePlayer(GetUnitName("player", true))
    end
    
    -- 构建待查询列表
    for i = 1, numGroupMembers do
        local unit = unitPrefix .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            table.insert(query.pendingQueries, unit)
        end
    end
    -- ATC:Debug("QueryTeamAchievement  pendingQueries count :"..tostring(#(self.currentQuery.pendingQueries)))

    if #query.pendingQueries <= 0 then
        -- 没有其他玩家需要查询，直接报告结果
        self:ReportResults()
    else
        query.isQuerying = true
        self:Print("开始查询团队成员的成就完成情况...")
        self:StartNextQuery()
        
        -- 设置总超时（备用，防止某些情况下查询卡住）
        query.overallTimeout = C_Timer.After(30, function()
            if query.isQuerying then
                self:Debug("查询总超时，强制结束查询")
                self:ReportResults(true)
            end
        end)
    end
end

-- 开始下一个查询
function ATC:StartNextQuery()
    ATC:Debug("StartNextQuery")
    local query = self.currentQuery
    ClearAchievementComparisonUnit()
    
    if #query.pendingQueries == 0 then
        self:ReportResults()
        return
    end
    
    local unit = table.remove(query.pendingQueries, 1)
    query.currentUnit = unit
    
    -- 设置成就比较单位
    local success = false
    if UnitIsConnected(unit) then 
        success = SetAchievementComparisonUnit(unit)
        ATC:Debug(string.format("SetAchievementComparisonUnit unit:%s res:%s", unit, tostring(success)))
    end
    
    if success then
        -- 为当前查询设置单独的超时（3秒）
        query.currentTimeout = C_Timer.After(3, function()
            if query.currentUnit == unit then
                ATC:Debug(string.format("查询超时: %s", unit))
                local name = GetUnitName(unit, true)
                query:AddFailedPlayer(name .. ":超时")
                query.currentUnit = nil
                query.currentTimeout = nil
                self:StartNextQuery()
            end
        end)
    else
        -- 设置失败，直接视为未完成
        local name = GetUnitName(unit, true)
        query:AddFailedPlayer(name .. ":失败")
        query.currentUnit = nil
        self:StartNextQuery()
    end
end


-- 报告结果
function ATC:ReportResults(isTimeout)
    ATC:Debug("ReportResults")
    if not self.currentQuery then return end
    
   local query = self.currentQuery
    
    -- 清理状态
    if query.currentTimeout then
        query.currentTimeout:Cancel()
        query.currentTimeout = nil
    end
    if query.overallTimeout then
        query.overallTimeout:Cancel()
        query.overallTimeout = nil
    end
    
    ClearAchievementComparisonUnit()
    query.isQuerying = false
    query.currentUnit = nil

    local message, messageExt

    local achievementName = ATC:AchievementNameFilter(query.currentAchievementName)
    if query.missingCount == 0 then
        message = string.format("果然[%s(%d)]这么简单的成就，大家都完成了。", achievementName, query.currentAchievementID)
    else
        message = string.format("怎么会还有人没有[%s(%d)]? %d/%d 人未完成。", 
                achievementName, query.currentAchievementID, query.missingCount, query.totalMembers)
    end
    if query.failedCount > 0 then 
        message = message .. string.format(" (%d人不在查询范围)", query.failedCount)
    end
    
    self.currentQuery = nil

    ATC:Debug(message)

    local chatType = IsInRaid() and "RAID" or "PARTY"
    ATC:Debug("ReportResults SendChatMessage " .. chatType)
    SendChatMessage(message, chatType)

    if #query.missingNames > 0 then
        messageExt = " 这些萌新是: " .. table.concat(query.missingNames, ", ")
        ATC:Debug(messageExt)
        C_Timer.After(self.MESSAGE_DELAY, function()
            SendChatMessage(messageExt, chatType)
        end)
    end

end

-- 打印消息
function ATC:Debug(msg)
    if self.debug then 
       DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00ACT_DEBUG|r: " .. msg)
    end
end

-- 打印消息
function ATC:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00成就团队检查|r: " .. msg)
end

-- QueryState 构造函数
function ATC:CreateQueryState(achievementID, achievementName)
    return {
        pendingQueries = {},  -- 待查询的玩家列表 {unit = {name, unit, achievementID}}
        missingNames = {},    -- 未完成成就的玩家名单
        failedNames = {},     -- 查询失败列表
        totalMembers = 0,     -- 总团队成员数
        completeCount = 0,    -- 完成成就的人数
        missingCount = 0,     -- 未完成成就的人数
        failedCount = 0,
        currentAchievementID = achievementID,
        currentAchievementName = achievementName,
        currentTimeout = nil, -- 当前查询的超时计时器
        overallTimeout = nil, -- 整体查询的超时计时器
        currentUnit = nil,    -- 用于unit超时的判断
        isQuerying = false,   -- 用于总体超时的判断
        
        -- 添加缺失玩家
        AddMissingPlayer = function(self, playerName)
            table.insert(self.missingNames, playerName)
            self.missingCount = self.missingCount + 1
            ATC:Debug(playerName .. " 未完成")
        end,
        
        -- 添加完成玩家
        AddCompletePlayer = function(self, playerName)
            self.completeCount = self.completeCount + 1
            ATC:Debug(playerName .. "查询失败")
        end,

        AddFailedPlayer = function(self, playerName)
            table.insert(self.failedNames, playerName)
            self.failedCount = self.failedCount + 1 
            ATC:Debug(playerName .. "已完成")
        end
    }
end

function ATC:AchievementNameFilter(str)
    if #str == 0 then return str end
    return string.gsub(str, "^([%z\1-\127\194-\244][\128-\191]*)", "%1.")
end

-- 初始化插件
ATC:Init()

-- Slash 命令
SLASH_ACHIEVEMENTTEAMCHECKER1 = "/atc"
SlashCmdList["ACHIEVEMENTTEAMCHECKER"] = function(msg)
    if msg == "debug" then
        ATC:Print("ATC进入调试模式，Hook状态: " .. tostring(ATC.isHooked))
        ATC.debug = true
    elseif msg == "hook" then
        ATC:HookAchievementUI()
    else
        ATC:Print("用法:")
        ATC:Print("/atc debug - 调试模式")
        ATC:Print("/atc hook - 手动重新Hook成就界面")
    end
end

-- 全局引用
_G.AchievementTeamChecker = ATC
