local modem = peripheral.find("modem")
local monitor = peripheral.find("monitor")
local chest = peripheral.find("minecraft:chest") or peripheral.find("minecraft:barrel") or peripheral.find("ironchest:iron_chest")
local tapeDrive = peripheral.find("tape_drive")

if not chest then
    error("Error: Chest not found! Check peripheral name.", 0)
end

-- Base URL for movie files (update for different movies)
local baseURL = "https://raw.githubusercontent.com/robertjojo123/shrek/refs/heads/main/video_part_"
local fpsTarget = 5
local frameDuration = 1000 / fpsTarget -- 5 FPS → 200ms per frame (milliseconds)
local framesPerVideo = 225
local linesPerFrame = 40  -- Each frame consists of 40 lines

function getMovieURL(index)
    return baseURL .. index .. ".nfv"
end

function clearOldVideos()
    fs.delete("/current_video.nfv")
    fs.delete("/next_video.nfv")
end

function downloadVideo(index)
    local url = getMovieURL(index)
    local localFile = "/current_video.nfv"

    shell.run("wget", url, localFile)
    return fs.exists(localFile) and localFile or nil
end

function loadVideo(videoFile)
    local videoData = {}
    for line in io.lines(videoFile) do
        table.insert(videoData, line)
    end
    local resolution = { videoData[1]:match("(%d+) (%d+)") }
    table.remove(videoData, 1)
    return videoData, resolution
end

function playVideo(videoFile, globalStartTime, videoIndex)
    local videoData, resolution = loadVideo(videoFile)

    -- First video starts at 1001, others start at 201
    local frameIndex = (videoIndex == 1) and 1001 or 201
    local nextFrameTime = globalStartTime + ((frameIndex - 1) / linesPerFrame) * frameDuration  -- Correct time sync

    while frameIndex <= #videoData do
        local currentTime = os.epoch("utc")
        local elapsedTime = currentTime - globalStartTime
        local expectedFrame = math.floor(elapsedTime / frameDuration) * linesPerFrame

        -- **Adjust frame index only if it's behind**
        if expectedFrame > frameIndex then
            frameIndex = expectedFrame
        end

        -- **Draw the frame**
        local frame = {}
        for i = 1, resolution[2] do
            if frameIndex > #videoData then break end
            table.insert(frame, videoData[frameIndex])
            frameIndex = frameIndex + 1
        end

        local parsedFrame = paintutils.parseImage(table.concat(frame, "\n"))
        paintutils.drawImage(parsedFrame, 1, 1)

        -- **Ensure proper yielding**
        os.queueEvent("frame")
        os.pullEvent("frame")

        -- **Hard lock FPS at 5**
        nextFrameTime = nextFrameTime + frameDuration
        local sleepTime = (nextFrameTime - os.epoch("utc")) / 1000
        if sleepTime > 0 then
            os.sleep(sleepTime) -- **Correctly sync frame rate**
        end
    end

    return os.epoch("utc") -- Return updated global time for next video
end

function correctTapeInserted(movieName)
    if tapeDrive and tapeDrive.getLabel then
        local label = tapeDrive.getLabel()
        return label and label:lower() == movieName:lower()
    end
    return false
end

function insertTape(movieName)
    if not tapeDrive then return false end

    if correctTapeInserted(movieName) then return true end

    local items = chest.list()
    for slot, item in pairs(items) do
        if item.name == "computronics:tape" then
            chest.pushItems(peripheral.getName(tapeDrive), slot, 1)
            os.sleep(1)

            if correctTapeInserted(movieName) then
                return true
            else
                tapeDrive.eject()
                os.sleep(1)
            end
        end
    end
    return false
end

function rewindTape()
    if tapeDrive and tapeDrive.getSize and tapeDrive.getPosition then
        if tapeDrive.getPosition() > 0 then
            tapeDrive.seek(-tapeDrive.getSize())
            os.sleep(2)
        end
    end
end

function ejectTape()
    if tapeDrive and tapeDrive.getLabel then
        tapeDrive.eject()
        os.sleep(1)
    end
end

function playMovie(movieName)
    clearOldVideos()
    local videoIndex = 1
    local globalStartTime = nil -- Will be set when audio starts

    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    if insertTape(movieName) then
        rewindTape()
        os.sleep(1)
        
        -- **Start the audio & sync global time exactly at this moment**
        tapeDrive.play()
        globalStartTime = os.epoch("utc") - 1000 -- Adjust for delay

        while true do
            local currentFile = downloadVideo(videoIndex)
            if not currentFile then break end

            local nextIndex = videoIndex + 1
            local nextFile = "/next_video.nfv"
            shell.run("wget", getMovieURL(nextIndex), nextFile, "&")

            -- **Start video playback and sync with real-time**
            globalStartTime = playVideo(currentFile, globalStartTime, videoIndex)
            fs.delete(currentFile)

            if fs.exists(nextFile) then
                fs.move(nextFile, "/current_video.nfv")
                videoIndex = nextIndex
            else
                break
            end
        end

        tapeDrive.stop()
        ejectTape()
    end
end

monitor.setTextScale(1)
term.redirect(monitor)
modem.open(100)

while true do
    local _, _, _, _, message = os.pullEvent("modem_message")
    if message:sub(1, 5) == "play_" then
        local movieName = message:sub(6)
        playMovie(movieName)
    end
end
