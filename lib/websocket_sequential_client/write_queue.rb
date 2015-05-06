# -*- coding: utf-8 -*-

require "thread"

module WebsocketSequentialClient
  class WriteQueue  #:nodoc:
    def initialize
      @mutex = Mutex.new
      @cond_var = ConditionVariable.new
      @result_mutex = Mutex.new
      @result_cond_var = ConditionVariable.new
      @frame_list = []
      @frame_result = {}
      @closed_value = nil
    end

    def close value
      @result_mutex.synchronize do
        @closed_value = value
        @result_cond_var.broadcast
      end
    end

    def push frame
      return if @closed_value

      @mutex.synchronize do
        @frame_list.push frame
        @cond_var.broadcast
      end
    end

    def pop
      @mutex.synchronize do
        @cond_var.wait @mutex while @frame_list.empty?

        return @frame_list.shift
      end
    end

    def push_result frame, result
      @result_mutex.synchronize do
        return if @closed_value

        @frame_result[frame.object_id] = result
        @result_cond_var.broadcast
      end
    end

    def pop_result frame
      @result_mutex.synchronize do
        until @frame_result.key?(frame.object_id) or @closed_value
          @result_cond_var.wait @result_mutex
        end

        return (@frame_result.delete(frame.object_id) || @closed_value)
      end
    end

    def process_frame frame
      push frame
      pop_result frame
    end
  end
end
