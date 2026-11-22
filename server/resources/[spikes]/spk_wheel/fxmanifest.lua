fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

description 'spk_wheel - spike S3: break/fix one wagon wheel (throwaway)'

dependency 'ox_lib'
shared_script '@ox_lib/init.lua'

client_script 'client.lua'
server_script 'server.lua'
