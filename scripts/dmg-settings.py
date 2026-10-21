import os.path

app_path = defines["app_path"]
app_name = os.path.basename(app_path)

format = "UDZO"
files = [app_path]
symlinks = {"Applications": "/Applications"}

icon = defines["volume_icon"]
background = defines["background"]

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

window_rect = ((200, 120), (660, 400))
default_view = "icon-view"

icon_size = 128
text_size = 12
icon_locations = {
    app_name: (170, 190),
    "Applications": (490, 190),
}
