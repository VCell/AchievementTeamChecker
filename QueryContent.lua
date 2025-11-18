
local ATC = _G.AchievementTeamChecker

-- 构建查询成就完成情况并通报的queryContent
function ATC:CreateCompleteQuery(id, name)
    return {
        missingNames = {},    -- 未完成成就的玩家名单
        failedNames = {},     -- 查询失败列表
        completeNames = {},   -- 完成成就的玩家名单
        completeCount = 0,    -- 完成成就的人数
        missingCount = 0,     -- 未完成成就的人数
        failedCount = 0,      -- 查询失败人数
        achievementID = id,
        achievementName = name,
        

        QueryForPlayer = function(self) 
            ATC:Debug("QueryForPlayer start" )
            local completed = select(13, GetAchievementInfo(self.achievementID))
            
            if not completed then
                self:addMissingPlayer(GetUnitName("player", true))
            else
                self:addCompletePlayer(GetUnitName("player", true))
            end
        end,

        OnQueryFailed = function(self, name)
            self:addFailedPlayer(name)
        end, 

        FetchResult = function(self, unit)
            ATC:Debug("FetchResult start")
            local isCompleted, _, _, _  = GetAchievementComparisonInfo(self.achievementID)
            local name = GetUnitName(unit, true)
            ATC:Debug(string.format("GetAchievementComparisonInfo unit:%s, name:%s, id:%d, result:%s", unit, name, self.achievementID, tostring(isCompleted)))

            if not isCompleted then
                self:addMissingPlayer(name)
            else
                self:addCompletePlayer(name)
            end
            -- local point = GetComparisonAchievementPoints()
            -- ATC:Debug(string.format("GetComparisonAchievementPoints unit:%s, %d", unit, point))
        end,

        GetReport = function(self)
            ATC:Debug("GetReport start")
            local message, messageExt

            local achievementName = ATC:AchievementNameFilter(self.achievementName)
            local totalMembers = self.missingCount + self.completeCount + self.failedCount
            if self.missingCount == 0 then

                local options = {
                    string.format("果然[%s]这么简单的成就，大家都完成了。", achievementName),
                    string.format("震惊！成就[%s]居然全员完成！你们是不是偷偷努力了？", achievementName),
                }
                message = options[math.random(1, #options)]

            elseif self.completeCount == 0 then

                local options = {
                    string.format("哇有这么难吗，团队里竟无人获得成就[%s]？", achievementName),
                    string.format("插件出BUG了吗，团队里怎么一个获得[%s]的都没有？", achievementName),  
                }
                message = options[math.random(1, #options)]

            elseif self.missingCount <= self.completeCount then 
 
                local options = {
                    string.format("怎么会还有人没有成就[%s]? %d/%d人未获得。", achievementName, self.missingCount, totalMembers),
                    string.format("[%s]成就点击就送，还没有的%d/%d人赶快去刷。", achievementName, self.missingCount, totalMembers),
                    string.format("[%s]成就有手就行，还没有的%d/%d人赶快去搞。", achievementName, self.missingCount, totalMembers),
                }
                message = options[math.random(1, #options)]
                messageExt = "未获得的萌新是:" .. table.concat(self.missingNames, ",")

            elseif self.missingCount > self.completeCount then  

                local options = {
                    string.format("哇太强了！我们队伍里竟然有%d/%d人完成了成就[%s]。", self.completeCount, totalMembers, achievementName),
                    string.format("[%s]成就怎么只有%d/%d人完成，不是点击就送吗？", achievementName, self.completeCount, self.totalMembers),
                    string.format("[%s]成就怎么只有%d/%d人完成，不是有手就行吗？", achievementName, self.completeCount, self.totalMembers),
                }
                message = options[math.random(1, #options)]
                messageExt = "完成的大佬是:" .. table.concat(self.completeNames, ",")

            end

            if self .failedCount > 0 then 
                message = message .. string.format(" (%d人不在查询范围)", self.failedCount)
            end
    
            return {message, messageExt}
        end,

        -- 添加缺失玩家
        addMissingPlayer = function(self, playerName)
            table.insert(self.missingNames, playerName)
            self.missingCount = self.missingCount + 1
            ATC:Debug(playerName .. " 未完成")
        end,
        
        -- 添加完成玩家
        addCompletePlayer = function(self, playerName)
            table.insert(self.completeNames, playerName)
            self.completeCount = self.completeCount + 1
            ATC:Debug(playerName .. "已完成")
        end,

        addFailedPlayer = function(self, playerName)
            table.insert(self.failedNames, playerName)
            self.failedCount = self.failedCount + 1 
            ATC:Debug(playerName .. "查询失败")
        end
    }
end

-- 构建查询成就点数，并通报成就点排名的queryContent
function ATC:CreatePointQuery(id, name)
    return {
        points = {}, -- name-point的map
        failedCount = 0,      -- 查询失败人数

        QueryForPlayer = function(self) 
            ATC:Debug("QueryForPlayer start" )
            local myPoints = GetTotalAchievementPoints()
            local name = GetUnitName("player", true)
            self.points[name] = myPoints
        end,

        OnQueryFailed = function(self, name)
            self.failedCount = self.failedCount + 1
        end, 

        FetchResult = function(self, unit)
            ATC:Debug("FetchResult start")
            local point = GetComparisonAchievementPoints()
            local name = GetUnitName(unit, true)
            ATC:Debug(string.format("GetComparisonAchievementPoints unit:%s, %d", unit, point))

            self.points[name] = point
        end,

        GetReport = function(self)
            ATC:Debug("GetReport start")
            
            -- 将点数数据转换为可排序的数组
            local ranking = {}
            for name, points in pairs(self.points) do
                table.insert(ranking, {
                    name = name,
                    points = points or 0
                })
            end
            
            -- 按点数降序排序
            table.sort(ranking, function(a, b)
                return a.points > b.points
            end)
            
            -- 生成排名消息
            local messages = {}
            
            if #ranking > 0 then
                -- 标题行
                table.insert(messages, "成就点数排名：")
                
                -- 排名内容
                for i, player in ipairs(ranking) do
                    if i <= 10 then -- 最多显示前10名
                        local rankText = string.format("%d. %s - %d点", i, player.name, player.points)
                        table.insert(messages, rankText)
                    end
                end
                
                -- 添加失败人数信息
                if self.failedCount > 0 then
                    table.insert(messages, string.format("(%d人查询失败)", self.failedCount))
                end

                local comments = {
                    "看来，人与人的差距，真的很大。"
                }
                table.insert(messages, comments[math.random(1, #comments)])
            else
                table.insert(messages, "暂无成就点数数据，可能大家都太低调了～")
            end
            
            return messages
        end,

    }
end

-- 构建查询成就点数，并通报成就点排名的queryContent
function ATC:CreateFeatQuery(id, name)
    return {
        points = {}, -- name-point的map
        failedCount = 0,      -- 查询失败人数

        QueryForPlayer = function(self) 
            ATC:Debug("QueryForPlayer start" )
            local _,complete,_ = GetCategoryNumAchievements(81)
            local name = GetUnitName("player", true)
            self.points[name] = complete
        end,

        OnQueryFailed = function(self, name)
            self.failedCount = self.failedCount + 1
        end, 

        FetchResult = function(self, unit)
            ATC:Debug("FetchResult start")
            local point = GetComparisonCategoryNumAchievements(81)
            local name = GetUnitName(unit, true)
            ATC:Debug(string.format("GetComparisonCategoryNumAchievements unit:%s, %d", unit, point))

            self.points[name] = point
        end,

        GetReport = function(self)
            ATC:Debug("GetReport start")
            
            -- 将点数数据转换为可排序的数组
            local ranking = {}
            for name, points in pairs(self.points) do
                table.insert(ranking, {
                    name = name,
                    points = points or 0
                })
            end
            
            -- 按点数降序排序
            table.sort(ranking, function(a, b)
                return a.points > b.points
            end)
            
            -- 生成排名消息
            local messages = {}
            
            if #ranking > 0 then
                -- 标题行
                table.insert(messages, "光辉事迹数量排名：")
                
                -- 排名内容
                for i, player in ipairs(ranking) do
                    if i <= 10 then -- 最多显示前10名
                        local rankText = string.format("%d. %s - %d", i, player.name, player.points)
                        table.insert(messages, rankText)
                    end
                end
                
                -- 添加失败人数信息
                if self.failedCount > 0 then
                    table.insert(messages, string.format("(%d人查询失败)", self.failedCount))
                end

                local comments = {
                    "看来，人与人的差距，真的很大。"
                }
                table.insert(messages, comments[math.random(1, #comments)])
            else
                table.insert(messages, "暂无成就点数数据，可能大家都太低调了～")
            end
            
            return messages
        end,

    }
end

function ATC:AchievementNameFilter(str)
    if #str == 0 then return str end
    return string.gsub(str, "^([%z\1-\127\194-\244][\128-\191]*)", "%1.")
end