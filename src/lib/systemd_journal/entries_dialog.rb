# Copyright (c) 2014 SUSE LLC.
#  All Rights Reserved.

#  This program is free software; you can redistribute it and/or
#  modify it under the terms of version 2 or 3 of the GNU General
#  Public License as published by the Free Software Foundation.

#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.   See the
#  GNU General Public License for more details.

#  You should have received a copy of the GNU General Public License
#  along with this program; if not, contact SUSE LLC.

#  To contact Novell about this file by physical or electronic mail,
#  you may find current contact information at www.suse.com

require 'yast'
require 'systemd_journal/query_presenter'
require 'systemd_journal/query_dialog'

Yast.import "UI"
Yast.import "Label"

module SystemdJournal
  # Dialog to display journal entries with several filtering options
  class EntriesDialog

    include Yast::UIShortcuts
    include Yast::I18n
    include Yast::Logger

    def initialize
      textdomain "systemd_journal"

      @query = QueryPresenter.new
      @search = ""
      read_journal_entries
    end
     
    # Displays the dialog
    def run
      return unless create_dialog

      begin
        return event_loop
      ensure
        close_dialog
      end
    end

  private

    # Draws the dialog
    def create_dialog
      Yast::UI.OpenDialog(
        Opt(:decorated, :defaultsize),
        VBox(
          # Header
          Heading(_("Journal entries")),
          # Filters
          Left(
            HBox(
              Label(_("Displaying entries with the following text")),
              HSpacing(1),
              InputField(Id(:search), Opt(:hstretch, :notify), "", @search)
            )
          ),
          ReplacePoint(Id(:query), query_description),
          VSpacing(0.3),
          # Log entries
          table,
          VSpacing(0.3),
          # Footer buttons
          HBox(
            HWeight(1, PushButton(Id(:filter), _("Change filter..."))),
            HStretch(),
            HWeight(1, PushButton(Id(:refresh), _("Refresh"))),
            HStretch(),
            HWeight(1, PushButton(Id(:cancel), Yast::Label.QuitButton))
          )
        )
      )
    end

    def close_dialog
      Yast::UI.CloseDialog
    end

    # Simple event loop. For each event generated by the interface, a method
    # named like the event but with the suffix '_callback' is called. If it
    # returns false, the loop is stopped and the whole dialog is closed.
    def event_loop
      loop do
        input = Yast::UI.UserInput
        method = :"#{input}_callback"
        if respond_to?(method, true)
          break unless send(method)
        else
          log.warn "Method #{method} not implemented"
        end
      end
    end

    # Table widget (plus wrappers) to display log entries
    def table
      Table(
        Id(:table),
        Opt(:keepSorting),
        Header(
          _("Time"),
          _("Process"),
          _("Message"),
        ),
        table_items
      )
    end

    def table_items
      # Reduce it to an array with only the visible fields
      entries_fields = @journal_entries.map do |entry|
        [
          entry.timestamp.strftime(QueryPresenter::TIME_FORMAT),
          entry.process_name,
          entry.message
        ]
      end
      # Grep for entries matching @search in any visible field
      entries_fields.select! do |fields|
        fields.any? {|f| Regexp.new(@search, Regexp::IGNORECASE).match(f) }
      end
      # Return the result as an array of Items
      entries_fields.map {|fields| Item(*fields) }
    end

    def query_description
      VBox(
        Left(Label(" - #{@query.interval_description}")),
        Left(Label(" - #{@query.filters_description}"))
      )
    end

    def redraw_query
      Yast::UI.ReplaceWidget(Id(:query), query_description)
    end

    def redraw_table
      Yast::UI.ChangeWidget(Id(:table), :Items, table_items)
    end

    # Event callback for quit button and window closing
    def cancel_callback
      false
    end

    # Event callback for the 'change filter' button.
    def filter_callback
      read_query
      read_journal_entries
      redraw_query
      redraw_table
      true
    end

    # Event callback for change in the content of the search box
    def search_callback
      read_search
      redraw_table
      true
    end

    # Event callback for the 'refresh' button
    def refresh_callback
      read_journal_entries
      redraw_table
      true
    end

    # Asks the user the new query options using SystemdJournal::QueryDialog.
    #
    # @see SystemdJournal::QueryDialog
    def read_query
      query = QueryDialog.new(@query).run
      if query
        @query = query
        log.info "New query is #{@query}."
      else
        log.info "QueryDialog returned nil. Query is still #{@query}."
      end
    end

    # Gets the new search string from the interface
    def read_search
      @search = Yast::UI.QueryWidget(Id(:search), :Value)
      log.info "Search string set to '#{@search}'"
    end

    # Reads the journal entries from the system
    def read_journal_entries
      @journal_entries = @query.entries
      log.info "Call to journalctl with '#{@query.journalctl_args}' returned #{@journal_entries.size} entries."
    end
  end
end
