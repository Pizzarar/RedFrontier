fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

description 'spk_camp: throwaway spike. Outlaw camp spawn + OneSync ownership'

dependency 'ox_lib'
shared_script '@ox_lib/init.lua'
shared_script 'config.lua'
server_script 'server.lua'
client_script 'client.lua'
