fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rs-tunerchip'
author 'Reality Sucks RP'
description 'Server-authoritative vehicle-bound drift controller with stock-relative handling profiles.'
version '3.1.2'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'bridge/client.lua',
    'client.lua'
}

server_scripts {
    'server.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/app.css',
    'html/app.js',
    'html/assets/*'
}

-- UI helpers resolve through ox_lib.
-- Framework integrations are handled internally at runtime.
dependencies {
    'ox_lib'
}