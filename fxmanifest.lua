fx_version 'cerulean'
game 'gta5'

name 'Surge Pops'
version '2.0.0'

lua54 'yes'

client_scripts {
    'cl-2Step.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'sv-2Step.lua'
}