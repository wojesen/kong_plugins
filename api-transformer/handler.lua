local access = require "kong.plugins.api-transformer.access"


local ApiTransformerHandler = {
  VERSION  = "1.3.0",
  PRIORITY = 801,
}


function ApiTransformerHandler:access(conf)
  access.execute(conf)
end


return ApiTransformerHandler
