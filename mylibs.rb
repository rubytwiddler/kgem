#
#  My library
#
#   Qt & other miscs

require 'singleton'
require 'korundum4'

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

    def addWidgetAtRight(*w)
        w.unshift(nil)
        addWidgetWithNilStretch(*w)
    end
end


#
class VBoxLayoutWidget < Qt::Widget
    def initialize(parent=nil)
        @layout = Qt::VBoxLayout.new
        super(parent)
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

    def addWidgetAtRight(*w)
        @layout.addWidgetAtRight(*w)
    end

    def addWidgetAtCenter(*w)
        @layout.addWidgetAtCenter(*w)
    end

    def layout
        @layout
    end
end

class HBoxLayoutWidget < Qt::Widget
    def initialize(parent=nil)
        @layout = Qt::HBoxLayout.new
        super(parent)
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

#--------------------------------------------------------------------------
#
#
class SettingsBase < KDE::ConfigSkeleton
    include Singleton

    # @sym : instance symbol to be added.
    def addBoolItem(sym, default=true)
        name = sym.to_s
        valueMethod = 'value'
        itemNewMethod = 'ItemBool'
        defineItem(sym, valueMethod, itemNewMethod, default)
    end

    def addStringItem(sym, default="")
        valueMethod = 'toString'
        itemNewMethod = 'ItemString'
        defineItem(sym, valueMethod, itemNewMethod, default.squote)
    end

    def addUrlItem(sym, default=KDE::Url.new)
        if default.kind_of? String then
            default = KDE::Url.new(default)
        end
        valueMethod = 'value'
        itemNewMethod = 'ItemUrl'
        defineItem(sym, valueMethod, itemNewMethod, default)
    end

    def defineItem(name, valueMethod, itemNewMethod, default)
        self.class.class_eval %Q{
            def #{name}
                @#{name} = findItem('#{name}').property.#{valueMethod}
            end

            def set#{name}(v)
                item = findItem('#{name}')
                unless item.immutable?
                    item.property = @#{name} = Qt::Variant.fromValue(v)
                end
            end

            def #{name}=(v)
                set#{name}(v)
            end
        }
        instance_variable_set "@#{name}",  default
        item = eval %Q{
            #{itemNewMethod}.new(currentGroup, '#{name}',
                  @#{name}, @#{name})
        }
        addItem(item)
    end
end


#--------------------------------------------------------------------------
#
#
# class Hash
#     alias   :old_blaket :[]
#     def [](key)
#         unless key.kind_of?(Regexp)
#             return old_blaket(key)
#         end
# 
#         retk, retv = self.find { |k,v| k =~ key }
#         retv
#     end
# end


class String
    def double_quote
        '"' + self + '"'
    end
    alias   :dquote :double_quote

    def single_quote
        "'" + self + "'"
    end
    alias   :squote :single_quote
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
 