module IssuesTag
  # Writes the "Tags changed" line of the issue History when tags are changed
  # through the issue form or bulk edit. (The inline editor on the issue page
  # does the same through RfFluxTags::IssueTags.replace.)
  #
  # Tags that end up on no record are kept: they are only ever deleted on
  # purpose, on the tag administration page or through the REST API.
  class ModelIssueHooks < Redmine::Hook::ViewListener
    # Issue form: the form already assigned issue[tag_list]; compare it with
    # what is stored and note the difference in the journal.
    def controller_issues_edit_before_save(context = {})
      issue = context[:issue]
      return unless issue.respond_to?(:tag_list) && issue.persisted?

      stored = Issue.find_by(id: issue.id)
      return unless stored

      RfFluxTags::IssueTags.add_history(issue, stored.tag_list.to_a, issue.tag_list.to_a)
    end

    # Bulk edit: tags to add and tags to remove, applied to every selected issue.
    def controller_issues_bulk_edit_before_save(context = {})
      params = context[:params] || {}
      issue = context[:issue]
      add = RfFluxTags.parse_names(params[:rf_flux_tags_add])
      remove = RfFluxTags.parse_names(params[:rf_flux_tags_remove])
      return if add.empty? && remove.empty?
      unless RfFluxTags::IssueTags.allowed?(issue)
        # asked for, not allowed: the save fails instead of answering "Successful update" with nothing changed
        issue.rf_flux_tags_refusal = 'cannot be changed by you on this issue' if issue.respond_to?(:rf_flux_tags_refusal=)
        return
      end

      RfFluxTags::IssueTags.change(issue, add: add, remove: remove)
    end
  end
end
