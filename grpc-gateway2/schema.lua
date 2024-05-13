return {
  name = "grpc-gateway2",
  fields = {
    { config = {
      type = "record",
      fields = {
        {
          content = {
            type = "string",
            required = false,
            default = nil,
          }, },
        { service = {
            type = "string",
            required = true,
            default = nil,
          }, },
        { method = {
          type = "string",
          required = true,
          default = nil,
        }, },
      },
    }, },
  },
}
