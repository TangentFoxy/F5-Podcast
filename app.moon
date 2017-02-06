lapis = require "lapis"
db = require "lapis.db"

import respond_to from require "lapis.application"
import is_admin from require "helpers"
import insert from table

Episodes = require "models.Episodes"
Tracks = require "models.Tracks"
Users = require "users.models.Users"

class extends lapis.Application
    @before_filter =>
        u = @req.parsed_url
        if u.path != "/users/login"
            @session.redirect = "#{u.scheme}://#{u.host}#{u.path}"
        if @session.info
            @info = @session.info
            @session.info = nil

    @include "users/users"
    @include "githook/githook"

    layout: "default"

    "*": =>
        return redirect_to: @url_for("index")

    [index: "/(:page[%d])"]: =>
        episodes = Episodes\paginated "WHERE status = ? ORDER BY pubdate DESC", Episodes.statuses.published, per_page: 10
        page = tonumber(@params.page) or 1
        episodes = episodes\get_page page

        @html ->
            for episode in *episodes
                h2 episode.title
                h4 episode.pubdate\sub 1, 10

                script src: @build_url "static/js/marked.min.js"
                link rel: "stylesheet", href: @build_url "static/highlight/styles/solarized-dark.css"
                script src: @build_url "static/highlight/highlight.pack.js"
                script -> raw "
                    marked.setOptions({
                        highlight: function(code) { return hljs.highlightAuto(code).value; },
                        smartypants: true
                    });
                    hljs.initHighlightingOnLoad();
                "
                div id: "post_#{episode.id}"
                script -> raw "document.getElementById('post_#{episode.id}').innerHTML = marked('#{episode.description\gsub("\\", "\\\\\\\\")\gsub("'", "\\'")\gsub("\n", "\\n")\gsub("\r", "")}');"

                div ->
                    a href: @url_for("post", pubdate: episode.pubdate), "Full Post"
                    text " | "
                    a href: @build_url(episode.download_uri), target: "_blank", "Listen Now"

            --TODO navigation!

    "/post/:id[%d]": =>
        episode = Episodes\find id: @params.id
        return redirect_to: @url_for("post", pubdate: episode.pubdate), status: 301

    [post: "/post/:pubdate"]: =>
        episode = Episodes\find pubdate: @params.pubdate\gsub "%%20", " "
        unless episode.status == Episodes.statuses.published
            return redirect_to: @url_for("index")

        @html ->
            h2 episode.title
            h4 episode.pubdate\sub 1, 10
            p episode.description
            tracks = Tracks\find_all episode.tracklist
            ol ->
                for track in *tracks
                    li track.track
            div ->
                a href: @build_url(episode.download_uri), target: "_blank", "Listen Now"

    [rss: "/rss"]: =>
        --TODO actually RSS feed

        @html ->
            p "Coming soon! (I just haven't written a generator yet and I'm working on stuffs.)"

    [new: "/new"]: respond_to {
        before: =>
            unless @session.id
                @write redirect_to: @url_for "index"
            user = Users\find id: @session.id
            unless user and user.admin
                @write redirect_to: @url_for "index"

        GET: =>
            @html ->
                form {
                    action: @url_for "new"
                    method: "POST"
                    enctype: "multipart/form-data"
                }, ->
                    p "Title: "
                    input type: "text", name: "title"
                    p "Description: "
                    textarea cols: 80, rows: 13, name: "description"
                    p "Tracklist: "
                    textarea cols: 80, rows: 13, name: "tracklist"
                    p "File name: "
                    input type: "text", name: "file_name"
                    br!
                    element "select", name: "status", ->
                        for status in *Episodes.statuses
                            if status == Episodes.statuses.draft
                                option value: Episodes.statuses[status], selected: true, status
                            else
                                option value: Episodes.statuses[status], status
                    input type: "submit"

        POST: =>
            --title & description should exist, but don't need to be verified
            --tracklist needs to be processed (should not be processed if status is a draft!)
            --file_name needs to be turned into download_uri
            --depending on status option with draft/published, set different pubdate
            --TODO make a thing to handle drafts

            local pubdate
            tracks = {}
            --if @params.status == Episodes.statuses.published
            pubdate = db.format_date!
            for name in (@params.tracklist.."\n")\gmatch ".-\n"
                if track = Tracks\find track: name\sub 1, -2
                    track\update { playcount: track.playcount + 1 }
                    insert tracks, track.id
                else
                    track = Tracks\create {
                        track: name\sub(1, -2)
                        playcount: 1
                    }
                    insert tracks, track.id
            --else
            --    pubdate = "1970-01-01 00:00:00"

            episode = Episodes\create {
                title: @params.title
                description: @params.description
                download_uri: "static/mp3/#{@params.file_name}"
                status: @params.status
                pubdate: pubdate
                tracklist: db.array tracks
            }

            if episode.status == Episodes.statuses.published
                return redirect_to: @url_for("post", pubdate: episode.pubdate)
            else
                return redirect_to: @url_for("index")   --NOTE temporary
    }

    [tracklist: "/tracklist"]: =>
        tracks = Tracks\select "* ORDER BY playcount DESC"
        @html ->
            div ->
                a href: @url_for("tracklist_alphabetical"), "Alphabetical"
                if is_admin @
                    text " | "
                    a href: @url_for("tracklist_edit"), "Edit Tracks"
            element "table", ->
                tr ->
                    th "Artist - Title [Album]"
                    th "Play count"
                for track in *tracks
                    tr ->
                        td track.track
                        td track.playcount

    [tracklist_alphabetical: "/tracklist/alphabetical"]: =>
        tracks = Tracks\select "* ORDER BY track ASC"
        @html ->
            div ->
                a href: @url_for("tracklist"), "Play count"
                if is_admin @
                    text " | "
                    a href: @url_for("tracklist_edit"), "Edit Tracks"
            element "table", ->
                tr ->
                    th "Artist - Title [Album]"
                    th "Play count"
                for track in *tracks
                    tr ->
                        td track.track
                        td track.playcount

    [tracklist_edit: "/tracklist/edit"]: respond_to {
        before: =>
            unless @session.id
                @write redirect_to: @url_for "index"
            user = Users\find id: @session.id
            unless user and user.admin
                @write redirect_to: @url_for "index"

        GET: =>
            render: true

        POST: =>
            track = Tracks\find id: @params.id
            track\update {
                track: @params.track
                playcount: tonumber(@params.playcount)
            }

            @info = "Track updated."
            render: true
    }

    --"/run-once": =>
        --episodes = Episodes\select "*"
        --for episode in *episodes
        --    for i=1,#episode.tracklist
        --        if episode.tracklist[i] == 9 or episode.tracklist[i] == 10
        --            episode.tracklist[i] = 25
        --            episode\update {tracklist: db.array episode.tracklist}
        --track = Tracks\find id: 9
        --track\delete!
        --track = Tracks\find id: 10
        --track\delete!
        --@html -> p "Done."
