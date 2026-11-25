var selectedTags = [];

function updateSelectedTags() {
    selectedTags = [];
    $('.checkbox_toggle_selection').each(function() {
        if ($(this).prop('checked')) {
            $(this).addClass('checked-checkbox');
            selectedTags.push($(this).val());
        } else {
            $(this).removeClass('checked-checkbox');
        }
    });
    toggleEditButtons();
    toggleDeleteIcons();
}

function updateSelectedTagsIssue() {
    selectedTags = [];
    $('.checkbox_toggle_selection_issue').each(function() {
        if ($(this).prop('checked')) {
            $(this).addClass('checked-checkbox');
            selectedTags.push($(this).val());
        } else {
            $(this).removeClass('checked-checkbox');
        }
    });
    toggleEditButtonsIssue();
    toggleDeleteIconsIssue();
}

function updateSelectedTagsProject() {
    selectedTags = [];
    $('.checkbox_toggle_selection_project').each(function() {
        if ($(this).prop('checked')) {
            $(this).addClass('checked-checkbox');
            selectedTags.push($(this).val());
        } else {
            $(this).removeClass('checked-checkbox');
        }
    });
    toggleEditButtonsProject();
    toggleDeleteIconsProject();
}

function updateSelectedTagsTime() {
    selectedTags = [];
    $('.checkbox_toggle_selection_time').each(function() {
        if ($(this).prop('checked')) {
            $(this).addClass('checked-checkbox');
            selectedTags.push($(this).val());
        } else {
            $(this).removeClass('checked-checkbox');
        }
    });
    toggleEditButtonsTime();
    toggleDeleteIconsTime();
}

function updateSelectedTagsPassword() {
    selectedTags = [];
    $('.checkbox_toggle_selection_password').each(function() {
        if ($(this).prop('checked')) {
            $(this).addClass('checked-checkbox');
            selectedTags.push($(this).val());
        } else {
            $(this).removeClass('checked-checkbox');
        }
    });
    toggleEditButtonsPassword();
    toggleDeleteIconsPassword();
}

// rtg-010: every tab renders on the same page, so the right-clicked checkbox
// (not a tag id, which can appear in several tabs) says which list it is.
function tagsTabFor(checkbox) {
    if (checkbox.hasClass('checkbox_toggle_selection_password')) {
        return 'password_entry';
    } else if (checkbox.hasClass('checkbox_toggle_selection_time')) {
        return 'time_entry';
    } else if (checkbox.hasClass('checkbox_toggle_selection_project')) {
        return 'project';
    }
    return 'issue';
}

function updateSelectedTagsFor(tab) {
    if (tab === 'password_entry') {
        updateSelectedTagsPassword();
    } else if (tab === 'time_entry') {
        updateSelectedTagsTime();
    } else if (tab === 'project') {
        updateSelectedTagsProject();
    } else {
        updateSelectedTagsIssue();
    }
}

function toggleEditButtonsIssue() {
    if (selectedTags.length > 1) {
        $('.icon-edit-issue').hide();
    } else {
        $('.icon-edit-issue').show();
    }
}

function toggleEditButtonsProject() {
    if (selectedTags.length > 1) {
        $('.icon-edit-project').hide();
    } else {
        $('.icon-edit-project').show();
    }
}

function toggleEditButtonsTime() {
    if (selectedTags.length > 1) {
        $('.icon-edit-time').hide();
    } else {
        $('.icon-edit-time').show();
    }
}

function toggleEditButtonsPassword() {
    if (selectedTags.length > 1) {
        $('.icon-edit-password').hide();
    } else {
        $('.icon-edit-password').show();
    }
}

function toggleEditButtons() {
    if (selectedTags.length > 1) {
        $('.icon-edit').hide();
    } else {
        $('.icon-edit').show();
    }
}

function toggleDeleteIcons() {
    var checkboxesChecked = $('.checkbox_toggle_selection:checked').length > 1;
    $('.icon-del').each(function() {
        var checkbox = $(this).closest('tr').find('.checkbox_toggle_selection');
        if (checkboxesChecked && !checkbox.prop('checked')) {
            $(this).css({
                'pointer-events': 'none',
                'opacity': '0.5'
            });
        } else {
            $(this).css({
                'pointer-events': 'auto',
                'opacity': '1'
            });
        }
    });
}

function toggleDeleteIconsIssue() {
    var checkboxesChecked = $('.checkbox_toggle_selection_issue:checked').length > 1;
    $('.icon-del-issue').each(function() {
        var checkbox = $(this).closest('tr').find('.checkbox_toggle_selection_issue');
        if (checkboxesChecked && !checkbox.prop('checked')) {
            $(this).css({
                'pointer-events': 'none',
                'opacity': '0.5'
            });
        } else {
            $(this).css({
                'pointer-events': 'auto',
                'opacity': '1'
            });
        }
    });
}

function toggleDeleteIconsProject() {
    var checkboxesChecked = $('.checkbox_toggle_selection_project:checked').length > 1;
    $('.icon-del-project').each(function() {
        var checkbox = $(this).closest('tr').find('.checkbox_toggle_selection_project');
        if (checkboxesChecked && !checkbox.prop('checked')) {
            $(this).css({
                'pointer-events': 'none',
                'opacity': '0.5'
            });
        } else {
            $(this).css({
                'pointer-events': 'auto',
                'opacity': '1'
            });
        }
    });
}

function toggleDeleteIconsTime() {
    var checkboxesChecked = $('.checkbox_toggle_selection_time:checked').length > 1;
    $('.icon-del-time').each(function() {
        var checkbox = $(this).closest('tr').find('.checkbox_toggle_selection_time');
        if (checkboxesChecked && !checkbox.prop('checked')) {
            $(this).css({
                'pointer-events': 'none',
                'opacity': '0.5'
            });
        } else {
            $(this).css({
                'pointer-events': 'auto',
                'opacity': '1'
            });
        }
    });
}

function toggleDeleteIconsPassword() {
    var checkboxesChecked = $('.checkbox_toggle_selection_password:checked').length > 1;
    $('.icon-del-password').each(function() {
        var checkbox = $(this).closest('tr').find('.checkbox_toggle_selection_password');
        if (checkboxesChecked && !checkbox.prop('checked')) {
            $(this).css({
                'pointer-events': 'none',
                'opacity': '0.5'
            });
        } else {
            $(this).css({
                'pointer-events': 'auto',
                'opacity': '1'
            });
        }
    });
}

$(document).ready(function() {
    function showContextMenu(x, y, tab) {
        var lang = $('html').attr('lang');
        var destroyText = (lang === 'ar') ? 'تدمير' : 'Delete';
        var useSpriteIcons = !!window.fluxTagsUseSpriteIcons;
        var iconsSpritePath = window.fluxTagsIconsSpritePath || '/assets/icons.svg';
        if ($('.list.issues')) {
            $('#context-menu').remove();
            var contextMenu = $('<div>').attr('id', 'context-menu');
            var ulList = $('<ul>'); 
            var listItem = $('<li>').addClass('destroy-tag');
            var destroyLink = $('<a href="#">')
                .addClass('rf-icon-link icon icon-del')
                .toggleClass('rf-icon-sprite', useSpriteIcons);

            if (useSpriteIcons) {
                destroyLink.html(
                    '<svg class="s18 icon-svg" aria-hidden="true">' +
                    '<use href="' + iconsSpritePath + '#icon--del"></use>' +
                    '</svg><span class="icon-label">' + destroyText + '</span>'
                );
            } else {
                destroyLink.text(destroyText);
            }

            destroyLink.on('click', function(e) {
                e.preventDefault();
                destroyTags(selectedTags, tab);
            });
            listItem.append(destroyLink);
            ulList.append(listItem); 
            contextMenu.append(ulList);
            $('body').append(contextMenu);
    
            var menuWidth = contextMenu.outerWidth();
            var menuHeight = contextMenu.outerHeight();
            var windowWidth = $(window).width();
            var windowHeight = $(window).height();
            var scrollTop = $(window).scrollTop();
            var scrollLeft = $(window).scrollLeft();
            if (x + menuWidth > windowWidth + scrollLeft) {
                x = windowWidth + scrollLeft - menuWidth - 10;
            }
            if (y + menuHeight > windowHeight + scrollTop) {
                y = windowHeight + scrollTop - menuHeight - 10; // 10px padding from the edge
            }
    
            contextMenu.css({
                top: y + 'px',
                left: x + 'px'
            });
        }
    }    

    $('.checkbox_toggle_selection_issue').on('click', function(e) {
        updateSelectedTagsIssue();
    });
    $('.checkbox_toggle_selection_time').on('click', function(e) {
        updateSelectedTagsTime();
    });
    $('.checkbox_toggle_selection_project').on('click', function(e) {
        updateSelectedTagsProject();
    });
    $('.checkbox_toggle_selection_password').on('click', function(e) {
        updateSelectedTagsPassword();
    });

    window.delete_tag = function(tag_id, tab) {
        // A row's own Delete link must always target only that row's tag,
        // regardless of what else is checkbox-selected elsewhere on the page.
        // Bulk deletion of selectedTags is handled separately by the
        // context-menu's own click handler.
        destroyTags([tag_id], tab);
    }

    $(document).on('contextmenu', function(e) {
        if ($(e.target).hasClass('checked-checkbox')) {
            console.log("demoworof")
            e.preventDefault();
            console.log(e.pageX,e.pageY,'sksksk')
            var tab = tagsTabFor($(e.target));
            updateSelectedTagsFor(tab);
            showContextMenu(e.pageX, e.pageY, tab);
        }
    });

    $(document).on('click', function(e) {
        if (!$(e.target).closest('#context-menu').length) {
            $('#context-menu').remove();
        }
    });
});

function destroyTags(selectedTags, tab) {
        var url = window.location.origin;
        $.ajax({
            url: url + '/tags',
            method: 'DELETE',
            // rtg-010: TagsController verifies the CSRF token again (SEC-001).
            headers: { 'X-CSRF-Token': $('meta[name="csrf-token"]').attr('content') },
            data: { tag_ids: selectedTags, tab: tab },
            success: function(response) {
                // Handle success response
            },
            error: function(xhr, status, error) {
                alert('Something went wrong while deleting the tag(s). Please try again.');
            }
        });
}

function tagsCheckboxIssue() {
    var toggleCheckbox = document.getElementById('toggle-checkbox-issue');
    var checkboxes = document.querySelectorAll('.checkbox_toggle_selection_issue');
    var shouldCheck = !toggleCheckbox.checked;

    checkboxes.forEach(function(checkbox) {
        checkbox.checked = shouldCheck;
    });

    toggleCheckbox.checked = shouldCheck;
    updateSelectedTagsIssue();
}

function tagsCheckboxProject() {
    var toggleCheckbox = document.getElementById('toggle-checkbox-project');
    var checkboxes = document.querySelectorAll('.checkbox_toggle_selection_project');
    var shouldCheck = !toggleCheckbox.checked;

    checkboxes.forEach(function(checkbox) {
        checkbox.checked = shouldCheck;
    });

    toggleCheckbox.checked = shouldCheck;
    updateSelectedTagsProject();
}

function tagsCheckboxTime() {
    var toggleCheckbox = document.getElementById('toggle-checkbox-time');
    var checkboxes = document.querySelectorAll('.checkbox_toggle_selection_time');
    var shouldCheck = !toggleCheckbox.checked;

    checkboxes.forEach(function(checkbox) {
        checkbox.checked = shouldCheck;
    });

    toggleCheckbox.checked = shouldCheck;
    updateSelectedTagsTime();
}

function showCustomConfirm(tag_id, tab) {
    let deleteRun = document.getElementById("delete-email-template");
    let overlay = document.getElementById("tag-overloay");
    deleteRun.style.display = "block";
    $('html').css('overflow-y', 'hidden');
    setTimeout(() => {
        deleteRun.classList.add("rtg-modal-visible");
        overlay.classList.add("rtg-overlay-visible");
    }, 5)
    document.getElementById('confirm-delete').onclick = function() {
        delete_tag(tag_id, tab);
    };
}

function closeDeleteTagModal() {
    $('html').css('overflow-y', 'auto');
    let closeRun = document.getElementById("delete-email-template");
    let overlay = document.getElementById("tag-overloay");
    $("body :tabbable").removeAttr("tabindex");
    closeRun.style.display = "none";
    closeRun.classList.remove("rtg-modal-visible");
    overlay.classList.remove("rtg-overlay-visible");
}

function tagsCheckboxPassword() {
    var toggleCheckbox = document.getElementById('toggle-checkbox-password');
    var checkboxes = document.querySelectorAll('.checkbox_toggle_selection_password');
    var shouldCheck = !toggleCheckbox.checked;

    checkboxes.forEach(function(checkbox) {
        checkbox.checked = shouldCheck;
    });

    toggleCheckbox.checked = shouldCheck;
    updateSelectedTagsPassword();
}

function validateKeyPress(event) {
    const regex = /^[a-zA-Z0-9\s]*$/;
    const key = String.fromCharCode(event.which);
    if (!regex.test(key)) {
        event.preventDefault();
        return false
    }
    return true;
}
