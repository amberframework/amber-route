module Amber::Router

  # A tree which stores and navigates routes associated with a web application.
  #
  # ```crystal
  # route_set = Amber::Router::RouteSet(Symbol).new
  # route_set.add "/get/", :root
  # route_set.add "/get/users/:id", :users
  # route_set.add "/get/users/:id/books", :users_books
  # route_set.add "/get/*/slug", :slug
  # route_set.add "/get/*", :catch_all
  #
  # p route_set # => a textual representation of the routing tree
  #
  # route_set.find("/get/users/3").payload           # => :users
  # route_set.find("/get/users/3/books").payload     # => :users_books
  # route_set.find("/get/coffee_maker/slug").payload # => :slug
  # route_set.find("/get/made/up/url").payload       # => :catch_all
  class RouteSet(T)
    @trunk : RouteSet(T)?
    @route : T?

    # A tree data structure (recursive). The initial construction has an segment
    # of "root" and no trunk. Subtrees must pass in these details upon creation.
    def initialize(@root = true)
      @segments = Array(Segment(T) | TerminalSegment(T)).new
      @insert_count = 0
    end

    # Look for or create a subtree matching a given segment.
    private def find_subtree!(segment : String) : Segment(T)
      if subtree = find_subtree segment
        subtree
      else
        case
        when segment.starts_with? ':'
          new_segment = VariableSegment(T).new(segment)
        when segment.starts_with? '*'
          new_segment = GlobSegment(T).new(segment)
        else
          new_segment = FixedSegment(T).new(segment)
        end

        @segments.push new_segment
        new_segment
      end
    end

    # Look for and return a subtree matching a given segment.
    private def find_subtree(url_segment : String) : Segment(T)?
      @segments.each do |segment|
        case segment
        when Segment
          break segment if segment.match? url_segment
        when TerminalSegment
          next
        else
          raise "finding subtree else oops"
        end
      end
    end

    # Add a route to the tree.
    def add(path, route : T) : Nil
      segments = split_path path
      terminal_segment = add(segments, route, path)
      terminal_segment.priority = @insert_count
      @insert_count += 1
    end

    # Recursively find or create subtrees matching a given path, and store the
    # application route at the leaf.
    protected def add(url_segments : Array(String), route : T, full_path : String) : TerminalSegment(T)
      unless url_segments.any?
        segment = TerminalSegment(T).new(route, full_path)
        @segments.push segment
        return segment
      end

      segment = find_subtree! url_segments.shift
      segment.route_set.add(url_segments, route, full_path)
    end

    def routes? : Bool
      @segments.any?
    end

    # Recursively search the routing tree for potential matches to a given path.
    def select_routes(path : Array(String), startpos = 0) : Array(TerminalSegment(T))
      accepting_terminal_segments = startpos == path.size
      can_recurse = startpos <= path.size - 1

      matches = [] of TerminalSegment(T)

      @segments.each do |segment|
        case segment
        when TerminalSegment
          matches << segment if accepting_terminal_segments

        when FixedSegment, VariableSegment
          next unless can_recurse
          next unless segment.match? path[startpos]

          matched_routes = segment.route_set.select_routes(path, startpos + 1)
          matched_routes.each do |matched_route|
            matches << matched_route
          end

        when GlobSegment
          matched_routes, _ = segment.route_set.reverse_select_routes(path, startpos)

          matched_routes.each do |matched_route|
            matches << matched_route
          end
        end
      end

      matches
    end

    # Recursively matches the right hand side of a glob segment.
    # Allows for routes like /a/b/*/d/e and /a/b/*/f/g to coexist.
    #
    # Importantly, each subtree must pass back up the remaining part
    # of the path so it can be matched against the parent, so this
    # method somewhat awkwardly returns:
    #
    #   { array of potential matches, position in path array : Int32)
    #
    # TODO move segment matching and recursion into Segment classes.
    protected def reverse_select_routes(path : Array(String), startpos, endpos = nil) : Tuple(Array(TerminalSegment(T)), Int32)
      no_matches = [] of T
      matches = [] of TerminalSegment(T)

      if endpos.nil?
        endpos = path.size - 1
      end

      @segments.each do |segment|
        case segment
        when TerminalSegment
          matches << segment

        when FixedSegment, VariableSegment
          new_matches, new_endpos = segment.route_set.reverse_select_routes path, startpos, endpos

          if new_matches.any? && segment.match? path[endpos]
            new_matches.each do |match|
              matches << match
            end
          end

        else
          raise "found glob or something else on reverse selection"
        end
      end

      {matches, endpos - 1}
    end

    # Find a route which is compatible with a path.
    def find(path : String) : RoutedResult(T)
      segments = split_path path
      matches = select_routes(segments)

      match = if matches.size > 1
        matches.sort.first
      elsif matches.size == 0
        nil
      else
        matches.first
      end

      RoutedResult(T).new(match)
    end

    # Produces a readable indented rendering of the tree, though
    # not really compatible with the other components of a deep object inspection
    def inspect(*, ts = 0)
      @segments.reduce("") do |s, segment|
        s + segment.inspect(ts: ts + 1)
      end
    end

    # Split a path by slashes, remove blanks, and compact the path array.
    # E.g. split_path("/a/b/c/d") => ["a", "b", "c", "d"]
    private def split_path(path : String) : Array(String)
      path.split("/").map do |segment|
        next nil if segment.blank?
        segment
      end.compact
    end

  end
end