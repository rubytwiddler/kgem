#
#  My library
#
#   Qt & other miscs

require 'Qt'

#
class Qt::HBoxLayout
    def addWidgets(*w)
        w.each do |e| self.addWidget(e) end
    end
end

class Qt::VBoxLayout
    def addWidgetWithNilStretch(*w)
        addLayout(
            Qt::HBoxLayout.new do |l|
                w.each do |i|
                    if i
                        l.addWidget(i)
                    else
                        l.addStretch
                    end
                end
            end
        )
    end
    
    def addWidgetAtCenter(*w)
        w.unshift(nil)
        w.push(nil)
        addWidgetWithNilStretch(*w)
    end

    def addWidgetAtLeft(*w)
        w.unshift(nil)
        addWidgetWithNilStretch(*w)
    end
end


#
class VBoxLayoutWidget < Qt::Widget
    def initialize(parent=nil,  f=nil)
        @layout = Qt::VBoxLayout.new(parent)
        super(parent, f)
        setLayout(@layout)
    end

    def addLayout(l)
        @layout.addLayout(l)
    end

    def addWidget(w)
        @layout.addWidget(w)
    end

    def addWidgetWithNilStretch(*w)
        @layout.addWidgetWithNilStretch(*w)
    end

    def addWidgetAtLeft(*w)
        @layout.addWidgetAtLeft(*w)
    end

    def addWidgetAtCenter(*w)
        @layout.addWidgetAtCenter(*w)
    end

    def layout
        @layout
    end
end

class HBoxLayoutWidget < Qt::Widget
    def initialize(parent=nil, f=nil)
        @layout = Qt::HBoxLayout.new(parent)
        super(parent, f)
        setLayout(@layout)
    end

    def addLayout(l)
        @layout.addLayout(l)
    end

    def addWidget(w)
        @layout.addWidget(w)
    end

    def layout
        @layout
    end
end

#
class Hash
    alias   old_blaket []
    def [](key)
        unless key.kind_of?(Regexp)
            return old_blaket(key)
        end

        retk, retv = self.find { |k,v| k =~ key }
        retv
    end
end

module Enumerable
    class Proxy
        instance_methods.each { |m| undef_method(m) unless m.match(/^__/) }
        def initialize(enum, method=:map)
            @enum, @method = enum, method
        end
        def method_missing(method, *args, &block)
            @enum.__send__(@method) {|o| o.__send__(method, *args, &block) }
        end
    end
    
    def every
        Proxy.new(self)
    end
end
 