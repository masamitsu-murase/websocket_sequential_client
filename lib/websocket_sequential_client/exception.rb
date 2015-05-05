# -*- coding: utf-8 -*-

module WebsocketSequentialClient
  class Error < StandardError
  end

  class SocketAlreadyClosed < Error
  end

  class HandshakeFailed < Error
  end

  class InvalidDataReceived < Error
  end
end
