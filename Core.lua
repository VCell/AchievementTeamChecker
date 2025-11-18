-- AchievementTeamChecker
local ATC = {
    achievementButtons = {},
    eventFrame = nil,
    isHooked = false,
    queryState = nil, 
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


-- QueryState 构造函数
function ATC:CreateQueryState(query)
    return {
        pendingQueries = {},  -- 待查询的玩家列表 
        totalMembers = 0,     -- 总团队成员数
        currentTimeout = nil, -- 当前查询的超时计时器
        overallTimeout = nil, -- 整体查询的超时计 时器
        currentUnit = nil,    -- 用于unit超时的判断
        isQuerying = false,   -- 用于总体超时的判断
        queryContent = query, 
    }
end

-- Hook 成就界面
function ATC:HookAchievementUI()
    if self.isHooked or not AchievementFrame then
        return
    end
    
    -- 方法1: 直接Hook成就按钮显示函数
    local achievementsFrame = AchievementFrame
    if achievementsFrame then 
        self:AddOverviewButton(achievementsFrame)
    else 
        self.Print("AddOverviewButton Failed")
    end

    if AchievementButton_DisplayAchievement then
        hooksecurefunc("AchievementButton_DisplayAchievement", function(button, category, achievement)
            self:AddQueryButtonToAchievement(button, category, achievement)
        end)
        self.isHooked = true
        self:Print("成就团队检查插件已加载.")
        return
    end
    
    -- -- 方法2: 监听成就框架显示事件
    -- self.eventFrame:RegisterEvent("ACHIEVEMENT_EARNED")
    -- self.eventFrame:SetScript("OnEvent", function(_, event, ...)
    --     if event == "ACHIEVEMENT_EARNED" then
    --         if AchievementFrame and AchievementFrame:IsVisible() then
    --             self:DelayHook()
    --         end
    --     elseif event == "INSPECT_ACHIEVEMENT_READY" then
    --         self:INSPECT_ACHIEVEMENT_READY(...)
    --     end
    -- end)
end

-- 延迟Hook以确保界面完全加载
function ATC:DelayHook()
    C_Timer.After(0.5, function()
        if not self.isHooked and AchievementButton_DisplayAchievement then
            hooksecurefunc("AchievementButton_DisplayAchievement", function(button, category, achievement)
                ATC:AddQueryButtonToAchievement(button, category, achievement)
            end)
            self.isHooked = true
            self:Print("成就团队检查插件已加载 DelayHook")
        end
    end)
end

-- 添加查询按钮到成就
function ATC:AddQueryButtonToAchievement(button, category, achievement)
    if not button or not achievement or self.isHooked == false then return end
    

    local id, name, _, _, _, _, _, description, _, icon = GetAchievementInfo(category, achievement)
    ATC:Debug(string.format("AddQueryButtonToAchievement name:%s category:%s achievement:%s",name, tostring(category), tostring(achievement)))
    button.description:SetText(description..' ID: '..id)

    if not id then return end
    
    -- 创建查询按钮
    local queryButton = button.queryButton
    if not queryButton then
        queryButton = CreateFrame("Button", nil, button, "UIPanelButtonTemplate")
        queryButton:SetSize(80, 22)
        queryButton:SetText("团队查询")
        queryButton:SetPoint("TOPRIGHT", button, "TOPRIGHT", -75, -5)
        queryButton:SetFrameLevel(button:GetFrameLevel() + 1)
        queryButton:SetToplevel(true)
        
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
        local query = ATC:CreateCompleteQuery(id, name)
        ATC:QueryTeamAchievement(query)
    end)
    queryButton:Show()
end

--测试
function ATC:AddOverviewButton(parentFrame)
    -- 创建团队检查按钮
    local pointsButton = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
    pointsButton:SetSize(80, 22)
    pointsButton:SetText("点数排名")
    pointsButton:SetFrameStrata("HIGH")
    pointsButton:SetToplevel(true)
    pointsButton:SetPoint("TOP", AchievementFrame, "TOP", -15, -10)
    pointsButton:SetScript("OnClick", function()
        local query = ATC:CreatePointQuery()
        ATC:QueryTeamAchievement(query)
    end)
    pointsButton:SetNormalFontObject("GameFontNormal")
    pointsButton:SetHighlightFontObject("GameFontHighlight")
    pointsButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("成就点数排名")
        GameTooltip:AddLine("检查团队中所有人的成就点数并通报排名", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    
    pointsButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    pointsButton:Show()

    local featButton = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
    featButton:SetSize(80, 22)
    featButton:SetText("光辉排名")
    featButton:SetFrameStrata("HIGH")
    featButton:SetToplevel(true)
    featButton:SetPoint("LEFT", pointsButton, "RIGHT", 0, 0) -- 放在点数按钮右边
    featButton:SetScript("OnClick", function()
        local query = ATC:CreateFeatQuery()
        ATC:QueryTeamAchievement(query)
    end)
    featButton:SetNormalFontObject("GameFontNormal")
    featButton:SetHighlightFontObject("GameFontHighlight")
    featButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("光辉事迹排名")
        GameTooltip:AddLine("检查团队中所有人的光辉事迹数量并通报排名", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    
    featButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    featButton:Show()

end

-- 注册成就检查事件
function ATC:RegisterAchievementEvents()
    self.eventFrame:RegisterEvent("INSPECT_ACHIEVEMENT_READY")
end

-- 成就数据就绪事件
function ATC:INSPECT_ACHIEVEMENT_READY(guid)
    ATC:Debug("INSPECT_ACHIEVEMENT_READY ".. guid)
    if not self.queryState then return end

    local query = self.queryState
    local unit = query.currentUnit
    
    if unit and guid == UnitGUID(unit) then
        -- 取消当前单位的超时计时器
        if query.currentTimeout then
            query.currentTimeout:Cancel()
            query.currentTimeout = nil
        end

        query.queryContent:FetchResult(unit)

        query.currentUnit = nil
        self:StartNextQuery()
    else
        ATC:Debug("INSPECT_ACHIEVEMENT_READY ERROR GUID:".. guid)
    end

end

-- 查询团队成就
function ATC:QueryTeamAchievement(queryContent)
    if not IsInGroup() and not IsInRaid() then
        self:Print("你不在团队中！")
        return
    end
    if self.queryState ~= nil then
        self:Print(string.format("当前成就检查中，稍后重试"))
        return
    end

    ATC:Debug(string.format("QueryTeamAchievement start"))
    -- 重置状态

    self:RegisterAchievementEvents()
    
    local unitPrefix = IsInRaid() and "raid" or "party"
    local numGroupMembers = GetNumGroupMembers()
    
    self.queryState = ATC:CreateQueryState(queryContent)
    local query = self.queryState
    query.totalMembers = numGroupMembers
    
    -- 检查自己
    query.queryContent:QueryForPlayer()

    -- 构建待查询列表 
    for i = 1, numGroupMembers do
        local unit = unitPrefix .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            table.insert(query.pendingQueries, unit)
        end
    end
    -- ATC:Debug("QueryTeamAchievement  pendingQueries count :"..tostring(#(self.queryState.pendingQueries)))

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
    local query = self.queryState
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
                query.queryContent:OnQueryFailed(name .. ":超时")
                query.currentUnit = nil
                query.currentTimeout = nil
                self:StartNextQuery()
            end
        end)
    else
        -- 设置失败，直接视为未完成
        local name = GetUnitName(unit, true)
        query.queryContent:OnQueryFailed(name .. ":失败")
        query.currentUnit = nil
        self:StartNextQuery()
    end
end


-- 报告结果
function ATC:ReportResults(isTimeout)
    ATC:Debug("ReportResults")
    if not self.queryState then return end
    
   local query = self.queryState
    
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

    self.queryState = nil
    
    local messages = query.queryContent:GetReport()
    ATC:Debug(tostring(messages))

    local chatType = IsInRaid() and "RAID" or "PARTY"

    for i, message in ipairs(messages) do
        C_Timer.After((i-1) * self.MESSAGE_DELAY, function()
            self:SafeSendChatMessage(message, chatType)
        end)
    end

end

function ATC:SafeSendChatMessage(message, chatType)
    local success, err = pcall(SendChatMessage, message, chatType)
    if not success then
        self:Print("消息发送失败: " .. tostring(err)) 
        self:Print("(团队消息) " .. message)
        return false
    end
    return true
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