# Utility methods for interacting with POSIX objects; mostly user and group
module Puppet::Util::POSIX
    # Retrieve a field from a POSIX Etc object.  The id can be either an integer
    # or a name.  This only works for users and groups.
    def get_posix_field(space, field, id)
        if id =~ /^\d+$/
            id = Integer(id)
        end
        prefix = "get" + space.to_s
        if id.is_a?(Integer)
            method = (prefix + idfield(space).to_s).intern
        else
            method = (prefix + "nam").intern
        end
        
        begin
            return Etc.send(method, id).send(field)
        rescue ArgumentError => detail
            # ignore it; we couldn't find the object
            return nil
        end
    end
    
    # Look in memory for an already-managed type and use its info if available.
    def get_provider_value(type, field, id)
        unless typeklass = Puppet::Type.type(type)
            raise ArgumentError, "Invalid type %s" % type
        end
        
        id = id.to_s
        
        chkfield = idfield(type)
        obj = typeklass.find { |obj|
            if id =~ /^\d+$/
                obj.should(chkfield).to_s == id ||
                    obj.is(chkfield).to_s == id
            else 
                obj[:name] == id
            end                    
        }
        
        return nil unless obj
        
        if obj.provider
            begin
                return obj.provider.send(field)
            rescue => detail
                if Puppet[:trace]
                    puts detail.backtrace
                    Puppet.err detail
                    return nil
                end
            end
        end
    end
    
    # Determine what the field name is for users and groups.
    def idfield(space)
        case Puppet::Util.symbolize(space)
        when :gr, :group: return :gid
        when :pw, :user: return :uid
        else
            raise ArgumentError.new("Can only handle users and groups")
        end
    end
    
    # Get the GID of a given group, provided either a GID or a name
    def gid(group)
        get_provider_value(:group, :gid, group) or get_posix_field(:gr, :gid, group)
    end

    # Get the UID of a given user, whether a UID or name is provided
    def uid(user)
        get_provider_value(:user, :uid, user) or get_posix_field(:pw, :uid, user)
    end
end

# $Id$