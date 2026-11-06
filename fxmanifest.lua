fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rs-tunerchip'
author 'William Brito - RealitySucksRP'
description 'Server-authoritative per-vehicle drift chip with smooth stock-relative handling profiles.'
version '3.1.2'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'bridge/rs_uiguard.lua',
    'bridge/rs_framework.lua',
    'bridge/client.lua',
    'client.lua'
}

server_scripts {
    'bridge/rs_framework.lua',
    'bridge/server.lua',
    'server.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/app.css',
    'html/app.js',
    'html/assets/*'
}

-- Framework and menu helpers are bundled locally and use ox_lib.
dependencies {
    'ox_lib'
}
