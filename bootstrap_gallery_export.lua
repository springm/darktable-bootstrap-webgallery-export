--[[Export module to create a web gallery from selected images

  copyright (c) 2025 Tino Mettler

  darktable is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  darktable is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this software.  If not, see <http://www.gnu.org/licenses/>.
]]

--[[
   TODO:
   - Lua: remove images dir if already existent
   - Lua: use share_dir once available in the API
   - Lua: implement "supported" callback to limit export to suited file formats
   - JS: implement zoom function as present in PhotoSwipe
   - Lua: translations
   - copyright headers
]]

local dt = require "darktable"
local df = require "lib/dtutils.file"
local json_pretty_print = require "lib/json_pretty_print"

-- - - - - - - - - - - - - - - - - - - - - - - -
-- C O N S T A N T S
-- - - - - - - - - - - - - - - - - - - - - - - -

local PS = dt.configuration.running_os == "windows" and  "\\"  or  "/"

-- title, first image w/o path, title, web-relative dir
-- don't forget to double % signs
html_start = [[<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>%s</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/css/bootstrap.min.css" rel="stylesheet"
    integrity="sha384-rbsA2VBKQhggwzxH7pPCaAqO46MgnOM80zW1RWuH61DGLwZJEdK2Kadq2F9CUG65" crossorigin="anonymous">
  <!-- Ekko Lightbox CSS -->
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/ekko-lightbox/5.3.0/ekko-lightbox.css" />
  <link href="res/user.css" rel="stylesheet">
  <style>
    .sprite {
      background-image: url('%s');
    }
  </style>
</head>
<body>
  <div id="header" class="sprite">
    <h1>%s</h1>
    <div id="nav">&nbsp;&nbsp;&nbsp;&nbsp;<a href='..'>Index</a>&nbsp;&nbsp;&nbsp;&nbsp;</div>
    <div id="zip">
      <button id="startButton" data-dir2zip="/%s">Zipfile erstellen</button><br />
      <div id="zipstatus" style="text-align:center;"></div>
    </div>
  </div>
  <div id="outer_lightgallery">
]]

html_end = [[  </div>
  <!-- jQuery, Popper, Bootstrap JS -->
  <script src="https://cdn.jsdelivr.net/npm/jquery@3.5.1/dist/jquery.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
  <!--<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/js/bootstrap.bundle.min.js"
    integrity="sha384-kenU1KFdBIe4zVF0s0G1M5b4hcpxyD9F7jL+jjXkk+Q2h455rYXK/7HAuoJl+0I4"
    crossorigin="anonymous"></script> -->
  <!-- <script src="https://cdn.jsdelivr.net/npm/bs5-lightbox@1.8.5/dist/index.bundle.min.js"></script> -->
  <!-- Ekko Lightbox JS -->
  <script src="https://cdnjs.cloudflare.com/ajax/libs/ekko-lightbox/5.3.0/ekko-lightbox.min.js"></script>
  <script>
    // Activate lightbox with gallery support for slideshow navigation
    $(document).on('click', '[data-toggle="lightbox"]', function (event) {
      event.preventDefault();
      $(this).ekkoLightbox({
        gallery: 'gallery'
      });
    });
  </script>
</body>
</html>
]]

-- - - - - - - - - - - - - - - - - - - - - - - -
-- M A I N
-- - - - - - - - - - - - - - - - - - - - - - - -

local temp = dt.preferences.read('web_gallery', 'title', 'string')
if temp == nil then temp = 'Darktable gallery' end

local title_widget = dt.new_widget("entry")
{
   text = temp
}

local temp = dt.preferences.read('web_gallery', 'destination_dir', 'string')
if temp == nil then temp = '' end

local dest_dir_widget = dt.new_widget("file_chooser_button")
{
   title = "select output folder",
   tooltip = "select output folder",
   value = temp,
   is_directory = true,
   changed_callback = function(this) dt.preferences.write('web_gallery', 'destination_dir', 'string', this.value) end
}

-- Function to find index of a value in size_options
local function find_index(value, tbl)
  for i, v in ipairs(tbl) do
    if v == value then
      return i
    end
  end
  return nil  -- not found
end

local size_options = { "2500", "3000", "3500" }
local header_footer_options = { "none", "header only", "footer only", "both" }

-- Read saved preference string
local saved_size = dt.preferences.read('web_gallery', "webgallery_image_size", "string")
-- Find corresponding index, default to 1 if not found
local selected_index = find_index(saved_size, size_options) or 1

local webgallery_image_size_widget = dt.new_widget("combobox") {
  label = "blog image size",
  tooltip = "Select image size for publication",
  selected = selected_index,  -- must be index, not string
  changed_callback = function(w)
    dt.preferences.write('web_gallery', "webgallery_image_size", "string", size_options[w.selected])
  end,
  table.unpack(size_options)
}

local saved_header_footer = dt.preferences.read('web_gallery', "webgallery_image_header_footer", "string")
-- Find corresponding index, default to 1 if not found
local selected_index = find_index(saved_header_footer, header_footer_options) or 1

local webgallery_image_header_footer_widget = dt.new_widget("combobox") {
  label = "header/footer",
  tooltip = "Select image size for publication",
  selected = selected_index,  -- must be index, not string
  changed_callback = function(w)
    dt.preferences.write('web_gallery', "webgallery_image_header_footer", "string", header_footer_options[w.selected])
  end,
  table.unpack(header_footer_options)
}

local gallery_widget = dt.new_widget("box")
{
    orientation=vertical,
    dt.new_widget("box") { orientation = "horizontal", 
                           dt.new_widget("label"){label = "gallery title", halign = "start"}, 
                           title_widget},
    dt.new_widget("box") { orientation = "horizontal", 
                           dt.new_widget("label"){label = "directory", halign = "start"},
                           dest_dir_widget},
    webgallery_image_header_footer_widget,
    webgallery_image_size_widget
}

local function copy_static_files(dest_dir)
    dt.print("copy static gallery files")
    gfsrc = dt.configuration.config_dir.."/bootstrap_gallery"
    gfiles = {
        "user.css",
        "user.js"
    }
    df.mkdir(dest_dir..PS..'res')
    for _, file in ipairs(gfiles) do
        df.file_copy(gfsrc..PS..file, dest_dir..PS.."res"..PS..file)
    end
end

local function get_file_name(file)
    return file:match("[^/]*.$")
end

local function export_thumbnail(image, filename)
    dt.print("export thumbnail image "..filename)
    exporter = dt.new_format("jpeg")
    exporter.quality = 90
    exporter.max_height = 512
    exporter.max_width = 512
    exporter:write_image(image, filename, true)
end

local function custom_tag_filter(tagstr, image)
    local blacklist = { darktable=true, style=true }

    -- split string by '|'
    local parts = {}
    for part in string.gmatch(tagstr, "([^|]+)") do
        table.insert(parts, part)
    end

    -- a) return "" if first part in blacklist
    if blacklist[parts[1]] then
        return ""
    end

    -- b) normally last part
    local last_part = parts[#parts]
    local second_last_part = parts[#parts - 1] or ""

    -- c) if last part is digits only, return second last part
    if last_part:match("^%d+$") then
        last_part = second_last_part
    end

    -- d) if first part is "where" and image has lat/lon, return OSM link
    if parts[1] == "where" and image and image.latitude and image.longitude then
        local lat, lon = image.latitude, image.longitude
        -- encode last_part for URL (basic encoding)
        local function url_encode(str)
        -- if (str) then
        --     str = str:gsub("\n", "\r\n")
        --     str = str:gsub("([^%w _%%%-%.~])", function(c) return string.format("%%%02X", string.byte(c)) end)
        --     str = str:gsub(" ", "+")
        -- end
        return str    
        end

        local label = url_encode(last_part)
        local url = string.format("https://www.openstreetmap.org/?mlat=%f&mlon=%f#map=18/%f/%f", lat, lon, lat, lon)
        return string.format("<a target='_blank' title='show on OSM' href='%s'>%s</a>", url, label)
    end
    return last_part
end

local function get_tagstring(image)
    tags = dt.tags.get_tags(image)
    local tagstring = ""
    -- dt.print_log(string.format("webgallery_image_header_footer_widget: %s", webgallery_image_header_footer_widget.value))
    if webgallery_image_header_footer_widget.value == "both" or 
       webgallery_image_header_footer_widget.value == "footer only" then
        for _, tag in ipairs(tags) do
            -- dt.print_log("  Tag: " .. tag.name)
            ts = custom_tag_filter(tag.name, image)
            if ts ~= "" then
                if tagstring ~= "" then
                    tagstring = tagstring..', '
                end
                tagstring = tagstring..ts
            end
        end
    end
    -- dt.print_log(string.format("tagstring: >%s<", tagstring))
    return tagstring
end

local html_body = ""
local function build_gallery(storage, images_table, extra_data)
    local size_value = webgallery_image_size_widget.value  -- or read it directly from preferences if applicable
    local max_size = tonumber(size_value) or 0
    local jpeg_exporter      = dt.new_format("jpeg")
    jpeg_exporter.max_height = max_size
    jpeg_exporter.max_width  = max_size

    local dest_dir = dest_dir_widget.value
    df.mkdir(dest_dir)
    df.mkdir(dest_dir..PS..'thumbnails')

    local images_ordered = extra_data["images"] -- process images in the correct order
    local html_body = ""
    for i, image in ipairs(images_ordered) do
        local fn = get_file_name(images_table[image])
        local filename = dest_dir..PS..fn
        local thumbname = dest_dir..PS..'thumbnails'..PS..fn
        jpeg_exporter:write_image(image, filename, false)
        export_thumbnail(image, thumbname)
        local title = ""
        if webgallery_image_header_footer_widget.value == "both" or 
            webgallery_image_header_footer_widget.value == "header only" then
            title = image.title
            if image.title == "" then
                title = image.filename
            end 
        end
        -- dt.print_log(string.format("title: >%s<", title))
        local tagstring = get_tagstring(image)  -- or: local tags = image:get_tags()
        html_body = html_body .. string.format( [[<a href="%s" data-toggle="lightbox" data-gallery="example-gallery" data-size="fullscreen"
      data-title="%s" data-footer="%s" class="col-sm-4">
      <img src="thumbnails/%s" class="thumbnail" /></a>
      ]], fn, title, tagstring, fn )
        if i == 1 then
            html_start = string.format(html_start, title_widget.text, fn, title_widget.text, get_file_name(dest_dir))
        end
    end
    local file = io.open(dest_dir..PS.."index.html", "w")
    file:write(html_start .. html_body .. html_end)
    file:close()
    copy_static_files(dest_dir)
end

local function show_status(storage, image, format, filename,
  number, total, high_quality, extra_data)
    dt.print(string.format("export image %i/%i", number, total))
end

local script_data = {}

script_data.metadata = {
    name = "website gallery (new)",
    purpose = "create a web gallery from exported images",
    author = "Markus Spring <me+darktable@markus-spring.de> basic idea from Tino Mettler <tino+darktable@tikei.de>",
    help = "https://docs.darktable.org/lua/stable/lua.scripts.manual/scripts/contrib/TODO"
}

script_data.destroy_method = nil -- set to hide for libs since we can't destroy them commpletely yet, otherwise leave as nil
script_data.restart = nil -- how to restart the (lib) script after it's been hidden - i.e. make it visible again
script_data.show = nil -- only required for libs since the destroy_method only hides them

local function destroy()
    dt.preferences.write('web_gallery', 'title', 'string', title_widget.text)
    dt.destroy_storage("module_webgallery")
end
script_data.destroy = destroy

local function initialize(storage, img_format, images, high_quality, extra_data)
    dt.preferences.write('web_gallery', 'title', 'string', title_widget.text)
    extra_data["images"] = images -- needed, to preserve images order
end

dt.register_storage("module_webgallery", "website gallery (new)", show_status, build_gallery, nil, initialize, gallery_widget)

return script_data
