# -*- coding: utf-8 -*-

require "thread"

module WebsocketSequentialClient
  class ReadQueue  #:nodoc:
    def initialize
      @mutex = Mutex.new
      @cond_var = ConditionVariable.new
      @frame_list = []
      @closed_value = nil
    end

    def close value
      @mutex.synchronize do
        @closed_value = value
        @cond_var.broadcast
      end
    end

    def available?
      @mutex.synchronize do
        return !(@frame_list.empty?)
      end
    end

    def push frame
      @mutex.synchronize do
        return if @closed_value

        @frame_list.push frame
        @cond_var.broadcast
      end
    end

    def pop
      @mutex.synchronize do
        until !(@frame_list.empty?) or @closed_value
          @cond_var.wait @mutex
        end

        if @frame_list.empty?
          return @closed_value
        else
          return @frame_list.shift
        end
      end
    end
  end
end
