# Manage NetInfo POSIX objects.  Probably only used on OS X, but I suppose
# it could be used elsewhere.

require 'puppet'
require 'puppet/provider/nameservice'

class Puppet::Provider::NameService
class NetInfo < Puppet::Provider::NameService
    # Attempt to flush the database, but this doesn't seem to work at all.
    def self.flush
        begin
            output = execute("/usr/sbin/lookupd -flushcache 2>&1")
        rescue Puppet::ExecutionFailure
            # Don't throw an error; it's just a failed cache flush
            Puppet.err "Could not flush lookupd cache: %s" % output
        end
    end

    # Similar to posixmethod, what key do we use to get data?  Defaults
    # to being the object name.
    def self.netinfodir
        if defined? @netinfodir
            return @netinfodir
        else
            return @model.name.to_s + "s"
        end
    end

    def self.finish
        case self.name
        when :uid:
            noautogen
        when :gid:
            noautogen
        end
    end

    # How to add an object.
    def addcmd
        creatorcmd("-create")
    end

    def creatorcmd(arg)
        cmd = [command(:niutil)]
        cmd << arg

        cmd << "/" << "/%s/%s" %
            [self.class.netinfodir(), @model[:name]]
        return cmd.join(" ")
    end

    def deletecmd
        creatorcmd("-destroy")
    end

    def ensure=(arg)
        super

        # Because our stupid type can't create the whole thing at once,
        # we have to do this hackishness.  Yay.
        if arg == :present
            # We need to generate the id if it's missing.
            @model.class.validstates.each do |name|
                next if name == :ensure
                unless val = @model.should(name)
                    if  (@model.class.name == :user and name == :uid) or
                        (@model.class.name == :group and name == :gid)
                        val = autogen()
                    else
                        # No value, and it's not required, so skip it.
                        next
                    end
                end
                self.send(name.to_s + "=", val)
            end
        end
    end

    # Retrieve a specific value by name.
    def get(param)
        hash = getinfo(false)
        if hash
            return hash[param]
        else
            return :absent
        end
    end

    # Retrieve everything about this object at once, instead of separately.
    def getinfo(refresh = false)
        if refresh or (! defined? @infohash or ! @infohash)
            states = [:name] + self.class.model.validstates
            states.delete(:ensure) if states.include? :ensure
            @infohash = report(*states)
        end

        return @infohash
    end

    def modifycmd(param, value)
        cmd = [command(:niutil)]

        cmd << "-createprop" << "/" << "/%s/%s" %
            [self.class.netinfodir, @model[:name]]

        if key = netinfokey(param)
            cmd << key << "'%s'" % value
        else
            raise Puppet::DevError,
                "Could not find netinfokey for state %s" %
                self.class.name
        end
        cmd.join(" ")
    end

    # Determine the flag to pass to our command.
    def netinfokey(name)
        name = symbolize(name)
        self.class.option(name, :key) || name
    end

    # Retrieve the data, yo.
    # FIXME This should retrieve as much information as possible,
    # rather than retrieving it one at a time.
    def report(*params)
        dir = self.class.netinfodir()
        cmd = [command(:nireport), "/", "/%s" % dir]

        # We require the name in order to know if we match.  There's no
        # way to just report on our individual object, we have to get the
        # whole list.
        params.unshift :name unless params.include? :name

        params.each do |param|
            if key = netinfokey(param)
                cmd << key.to_s
            else
                raise Puppet::DevError,
                    "Could not find netinfokey for state %s" %
                    self.class.name
            end
        end

        begin
            output = execute(cmd.join(" "))
        rescue Puppet::ExecutionFailure => detail
            Puppet.err "Failed to call nireport: %s" % detail
            return nil
        end

        output.split("\n").each { |line|
            values = line.split(/\t/)

            hash = {}
            params.zip(values).each do |param, value|
                next if value == '#NoValue#'
                hash[param] = if value =~ /^[-0-9]+$/
                    Integer(value)
                else
                    value
                end
            end

            if hash[:name] == @model[:name]
                return hash
            else
                next
            end

#
#            if line =~ /^(\w+)\s+(.+)$/
#                name = $1
#                value = $2.sub(/\s+$/, '')
#
#                if name == @model[:name]
#                    if value =~ /^[-0-9]+$/
#                        return Integer(value)
#                    else
#                        return value
#                    end
#                end
        }

        return nil
    end

    def retrieve
        raise "wtf?"
        @is = report() || :absent
    end

    def setuserlist(group, list)
        cmd = "#{command(:niutil)} -createprop / /groups/%s users %s" %
            [group, list.join(",")]
        begin
            output = execute(cmd)
        rescue Puppet::Execution::Failure => detail
            raise Puppet::Error, "Failed to set user list on %s: %s" %
                [group, detail]
        end
    end
end
end

# $Id$
