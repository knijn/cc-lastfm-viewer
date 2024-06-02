local monitor = peripheral.find("monitor")
local bigfont = require("bigfont")
local pngImage = require("png")
local data
local config = require("config")
local url = "https://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks&user=" .. config.user .. "&api_key=" .. config.api_key .. "&format=json&limit=2&extended=1"
local img
local colorResolution = config.colorResolution


local function convertToPNG(imageURL,xImageSize,yImageSize)
  local h, err = http.post(config.imgpush_api,"{\"url\":\"" .. imageURL .. "\"}",{["Content-Type"]="application/json"})
  print(config.imgpush_api)
  print(textutils.serialiseJSON({url = imageURL}))
  --print()
  if err then error(err) end
  local fileName = textutils.unserialiseJSON(h.readAll()).filename
  h.close()
  print("returned filename: " .. fileName)
  local h = http.get(config.imgpush_api .. "/" .. fileName .. "?w=" .. xImageSize.. "&h=" .. yImageSize,_,true)
  image = pngImage(nil,{input=h.readAll()})
  h.close()
  print(("pixel 1,1 has the colors r:%d g:%d b:%d"):format(image:get_pixel(1,1):unpack()))

  term.redirect(monitor)


  local pixelbox = require("pixelbox_lite").new(term.current())

  local function preprocess_palette(palette)
      local output = {}

      for i=1,#palette do
          local current_color = palette[i]

          local hex = current_color[1] + current_color[2]^2 + current_color[3]^16

          output[i] = {
              r = current_color[1],
              g = current_color[2],
              b = current_color[3],

              hex = hex
          }
      end

      return output
  end

  local lookup_cache = {}
  local function palette_lookup(palette,r,g,b)
      local closest_color
      local distance = math.huge

      for i=1,#palette do
          local color = palette[i]

          local test_distance = (color.r-r)^2 + (color.g-g)^2 + (color.b-b)^2
          if test_distance < distance then
              closest_color = i
              distance = test_distance
          end
      end

      return closest_color
  end

  local function round_colorspace(colorspace,r,g,b)
      return  math.ceil(r*colorspace.r_res),
              math.ceil(g*colorspace.g_res),
              math.ceil(b*colorspace.b_res)
  end

  local function generate_color_space(palette,red,green,blue)
      local colorspace = {
          r_res = red   - 1,
          g_res = green - 1,
          b_res = blue  - 1
      }

      for r_level=0,red-1 do
          local space_red_level = r_level/(red-1)

          local green_layer = {}
          colorspace[r_level] = green_layer
          for g_level=0,green-1 do
              local space_green_level = g_level/(green-1)

              local blue_layer = {}
              green_layer[g_level] = blue_layer
              for b_level=0,blue-1 do
                  local space_blue_level = b_level/(blue-1)

                  local palette_index = palette_lookup(palette,space_red_level,space_green_level,space_blue_level)

                  blue_layer[b_level] = palette_index
              end
          end
      end

      return colorspace
  end

  --local image = png("idfk.png")

  local palette = {}
  for i=1,16 do
      palette[i] = {term.getPaletteColor(2^(i-1))}
  end


  local function check_bounds(x,y,width,height)
      return x > 0 and y > 0 and x <= width and y <= height
  end

  local w,h = term.getSize()
  w,h = w*2,h*3

  local function lerp(a,b,t)
      return (1-t)*a + b*t
  end

  local res = colorResolution

  local processed_palette = preprocess_palette  (palette)
  local lookup_space      = generate_color_space(processed_palette,res,res,res)

  local canvas = pixelbox.CANVAS

  for x=1,image.width do
    for y=1,image.height do
      if check_bounds(x,y,w,h) then
        local r,g,b = image:get_pixel(x,y):unpack()
        local round_r,round_g,round_b = round_colorspace(lookup_space,r,g,b)

        local color = lookup_space[round_r][round_g][round_b]

        canvas[y][x] = 2^(color-1)
      end
    end
  end

  sleep(0)

  pixelbox:render()
  return palette
end


local function getData()
  local h, err = http.get(url)

  if not h then error(err) end
  data = textutils.unserialiseJSON(h.readAll())
  h.close()
  --print(textutils.serialise(data))
  --print("Latest song: " .. data.recenttracks.track[1].artist["#text"] .. " - ".. data.recenttracks.track[1].name)
  --local pngURL = data.recenttracks.track[1].image.

  local h = fs.open("data","w")
  h.write(textutils.serialise(data))
  h.close()
  print(data.recenttracks.track[1].image[1]["#text"])

end

local function draw()
  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.white)
  --monitor.clear()
  monitor.setTextScale(0.5)
  local oldTerm = term.current()
  local xSize, ySize = monitor.getSize()
  local maxRes = {xSize * 2, ySize * 3}
  local actualRes = 20 -- safe default
  local targetLine = ySize - 7
  if maxRes[1] < maxRes[2] then
    actualRes = maxRes[1]
    targetLine = (actualRes / 3) + 2

  elseif maxRes[1] > maxRes[2] then
    actualRes = maxRes[2]
    --targetLine = maxRes / 3 + 1
    -- there's no space at the bottom, develop a horizontal layout to fix this!
  else
    actualRes = maxRes[2]
    --targetLine = maxRes / 3 + 1
    -- ????
    -- the album art probably exactly fits
  end

  targetLine = math.ceil(targetLine) -- its better to be over than under in order to not cover the album art

  print("chose " .. actualRes .. "x" .. actualRes .. " and targetLine " .. targetLine)
  print("monitor character resolution: " .. xSize .. "x" .. ySize)
  print("monitor subpixel resolution: " .. maxRes[1] .. "x" .. maxRes[2])
  local palette = convertToPNG(data.recenttracks.track[1].image[4]["#text"],actualRes,actualRes)

  term.redirect(oldTerm)

  local title = data.recenttracks.track[1].name
  if data.recenttracks.track[1].loved == "1" then
    title = title .. " \3"
  end
  print(#title, (xSize / 3  - 4))
  local nowplaying
  --print(data.recenttracks.track[1]["@attr"].nowplaying)
  if data.recenttracks.track[1]["@attr"] and data.recenttracks.track[1]["@attr"].nowplaying == "true" then
    nowplaying =  true
  else
    nowplaying = false
  end
  for i=0,3 do
    monitor.clearLine(1,targetLine + i)
  end
  if #title < (xSize / 3  - 4) then


    monitor.setCursorPos(3,targetLine)
    term.redirect(monitor)
    bigfont.bigPrint(title)
    term.redirect(oldTerm)

    if nowplaying then
      monitor.setCursorPos(#title * 3 + 4,targetLine)
      monitor.write("LIVE")
    end
  else
    monitor.setCursorPos(3,targetLine + 1)
    monitor.write(title)
    if nowplaying then
      monitor.setCursorPos(3,ySize - 5)
      monitor.write("LIVE")
    end
  end
  monitor.setCursorPos(3,targetLine + 3)
  monitor.write(data.recenttracks.track[1].artist.name)

  monitor.setCursorPos(3,ySize - 5)

  if nowplaying == false then
    monitor.write("Not playing any music right now, this isn't live")
  else
    monitor.write("LastFM viewer by knijn under MIT license: github.com/knijn/cc-lastfm-viewer")
  end

  monitor.setCursorPos(3,ySize - 6)
  monitor.write("A display of songs that " .. config.user .. " is listening to.")
end

while true do
  getData()
  draw()
  sleep(10)
end