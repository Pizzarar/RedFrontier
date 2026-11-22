fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

description 'spk_chase: throwaway spike. 3 mounted AI riders chase the player wagon for 60s'

dependency 'ox_lib'
shared_script '@ox_lib/init.lua'
server_script 'server.lua'
client_script 'client.lua'
