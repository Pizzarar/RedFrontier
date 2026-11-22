fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

description 'spk_pelt - spike S4: is pelt/carcass quality readable, head vs body shot (throwaway)'

dependency 'ox_lib'
shared_script '@ox_lib/init.lua'

client_script 'client.lua'
server_script 'server.lua'
