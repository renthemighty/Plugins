jQuery(function($) {
    'use strict';

    // Request Queue and Rate Limiting System
    var wcrmRequestQueue = {
        queue: [],
        processing: false,
        lastRequestTime: 0,
        minDelay: 1000, // Minimum 1 second between requests

        add: function(requestFunc) {
            this.queue.push(requestFunc);
            this.process();
        },

        process: function() {
            if (this.processing || this.queue.length === 0) {
                return;
            }

            var now = Date.now();
            var timeSinceLastRequest = now - this.lastRequestTime;

            if (timeSinceLastRequest < this.minDelay) {
                // Wait before processing next request
                var self = this;
                setTimeout(function() {
                    self.process();
                }, this.minDelay - timeSinceLastRequest);
                return;
            }

            this.processing = true;
            this.lastRequestTime = Date.now();
            var requestFunc = this.queue.shift();

            var self = this;
            requestFunc().always(function() {
                self.processing = false;
                // Process next request after delay
                setTimeout(function() {
                    self.process();
                }, self.minDelay);
            });
        }
    };

    // Debounce function for search inputs
    function debounce(func, wait) {
        var timeout;
        return function() {
            var context = this, args = arguments;
            clearTimeout(timeout);
            timeout = setTimeout(function() {
                func.apply(context, args);
            }, wait);
        };
    }

    // Initialize Select2 for product search (add form)
    $('#wcrm-product').selectWoo({
        ajax: {
            url: wcrmData.ajaxurl,
            dataType: 'json',
            delay: 500,
            data: function(params) {
                return {
                    term: params.term,
                    action: 'wcrm_search_products',
                    security: wcrmData.nonce
                };
            },
            processResults: function(data) {
                return {
                    results: Object.keys(data).map(id => ({
                        id: id,
                        text: data[id]
                    }))
                };
            }
        },
        minimumInputLength: 1,
        placeholder: '-- Search for product --'
    });

    // Initialize Select2 for product search (manage section)
    $('#wcrm-product-search').selectWoo({
        ajax: {
            url: wcrmData.ajaxurl,
            dataType: 'json',
            delay: 500,
            data: function(params) {
                return {
                    term: params.term,
                    action: 'wcrm_search_products',
                    security: wcrmData.nonce
                };
            },
            processResults: function(data) {
                return {
                    results: Object.keys(data).map(id => ({
                        id: id,
                        text: data[id]
                    }))
                };
            }
        },
        minimumInputLength: 1,
        placeholder: '-- Search for product --'
    });

    // Initialize Select2 for user search
    $('#wcrm-user').selectWoo({
        ajax: {
            url: wcrmData.ajaxurl,
            dataType: 'json',
            delay: 500,
            data: function(params) {
                return {
                    term: params.term,
                    action: 'wcrm_search_users',
                    security: wcrmData.nonce
                };
            },
            processResults: function(data) {
                return {
                    results: Object.keys(data).map(id => ({
                        id: id,
                        text: data[id]
                    }))
                };
            }
        },
        minimumInputLength: 1,
        placeholder: '-- Search for user --'
    });

    // Toggle between existing user and custom name/email
    $('input[name="user_type"]').on('change', function() {
        if ($(this).val() === 'existing') {
            $('#existing-user-row').show();
            $('#custom-name-row, #custom-email-row').hide();
        } else {
            $('#existing-user-row').hide();
            $('#custom-name-row, #custom-email-row').show();
        }
    });

    // Add Review Form Submit
    $('#wcrm-add-form').on('submit', function(e) {
        e.preventDefault();

        var formData = {
            action: 'wcrm_add_review',
            security: wcrmData.nonce,
            product_id: $('#wcrm-product').val(),
            rating: $('input[name="rating"]:checked').val(),
            user_type: $('input[name="user_type"]:checked').val(),
            user_id: $('#wcrm-user').val(),
            custom_name: $('#wcrm-custom-name').val(),
            custom_email: $('#wcrm-custom-email').val(),
            review_text: tinyMCE.get('wcrm-review-text') ? tinyMCE.get('wcrm-review-text').getContent() : $('#wcrm-review-text').val(),
            review_date: $('#wcrm-review-date').val()
        };

        // Show loading state
        var $submitBtn = $(this).find('button[type="submit"]');
        var originalText = $submitBtn.text();
        $submitBtn.prop('disabled', true).text('Adding Review (queued)...');

        // Remove any existing messages
        $('.wcrm-message').remove();

        // Add to request queue
        wcrmRequestQueue.add(function() {
            $submitBtn.text('Adding Review...');
            return $.post(wcrmData.ajaxurl, formData)
                .done(function(response) {
                    if (response.success) {
                        // Show success message
                        $('#wcrm-add-form').before('<div class="wcrm-message success">' + response.data.message + '</div>');

                        // Reset form
                        $('#wcrm-add-form')[0].reset();
                        $('#wcrm-product, #wcrm-user').val(null).trigger('change');
                        $('input[name="rating"]').prop('checked', false);
                        if (tinyMCE.get('wcrm-review-text')) {
                            tinyMCE.get('wcrm-review-text').setContent('');
                        }

                        // Scroll to message
                        $('html, body').animate({
                            scrollTop: $('.wcrm-message').offset().top - 100
                        }, 500);

                        // Remove message after 5 seconds
                        setTimeout(function() {
                            $('.wcrm-message').fadeOut(function() {
                                $(this).remove();
                            });
                        }, 5000);
                    } else {
                        // Show error message
                        $('#wcrm-add-form').before('<div class="wcrm-message error">' + response.data + '</div>');

                        // Scroll to message
                        $('html, body').animate({
                            scrollTop: $('.wcrm-message').offset().top - 100
                        }, 500);
                    }
                })
                .fail(function() {
                    $('#wcrm-add-form').before('<div class="wcrm-message error">An error occurred. Please try again.</div>');
                })
                .always(function() {
                    $submitBtn.prop('disabled', false).text(originalText);
                });
        });
    });

    // Load Reviews for Product
    $('#wcrm-load-reviews').on('click', function() {
        var productId = $('#wcrm-product-search').val();

        if (!productId || productId == '0') {
            alert('Please select a product first');
            return;
        }

        // Show loading
        $('#wcrm-reviews-list').html('<div class="wcrm-loading">Loading reviews (queued)...</div>');

        // Add to request queue
        wcrmRequestQueue.add(function() {
            $('#wcrm-reviews-list').html('<div class="wcrm-loading">Loading reviews...</div>');
            return $.get(wcrmData.ajaxurl, {
                action: 'wcrm_list_reviews',
                security: wcrmData.nonce,
                product_id: productId
            })
            .done(function(response) {
                if (response.success) {
                    if (response.data.length === 0) {
                        $('#wcrm-reviews-list').html('<div class="wcrm-empty">No reviews found for this product.</div>');
                    } else {
                        var html = '';
                        response.data.forEach(function(review) {
                            var stars = getStarRating(review.rating);
                            html += '<div class="wcrm-review-item" data-comment-id="' + review.comment_id + '">';
                            html += '  <div class="wcrm-review-header">';
                            html += '    <div>';
                            html += '      <span class="wcrm-review-author">' + escapeHtml(review.author) + '</span>';
                            html += '      <span class="wcrm-review-email">(' + escapeHtml(review.author_email) + ')</span>';
                            html += '    </div>';
                            html += '    <div class="wcrm-review-rating">' + stars + '</div>';
                            html += '  </div>';
                            html += '  <div class="wcrm-review-content">' + review.review_full + '</div>';
                            html += '  <div class="wcrm-review-meta">';
                            html += '    <span class="wcrm-review-date">Posted on: ' + review.date + '</span>';
                            html += '    <div class="wcrm-review-actions">';
                            html += '      <button class="button wcrm-edit-review" data-comment-id="' + review.comment_id + '">Edit</button>';
                            html += '      <button class="button wcrm-delete-review" data-comment-id="' + review.comment_id + '">Delete</button>';
                            html += '    </div>';
                            html += '  </div>';
                            html += '</div>';
                        });
                        $('#wcrm-reviews-list').html(html);
                    }
                } else {
                    $('#wcrm-reviews-list').html('<div class="wcrm-message error">' + response.data + '</div>');
                }
            })
            .fail(function() {
                $('#wcrm-reviews-list').html('<div class="wcrm-message error">An error occurred. Please try again.</div>');
            });
        });
    });

    // Edit Review Button
    $(document).on('click', '.wcrm-edit-review', function() {
        var commentId = $(this).data('comment-id');
        var $btn = $(this);
        var originalText = $btn.text();
        $btn.prop('disabled', true).text('Loading...');

        // Add to request queue
        wcrmRequestQueue.add(function() {
            return $.get(wcrmData.ajaxurl, {
                action: 'wcrm_get_review',
                security: wcrmData.nonce,
                comment_id: commentId
            })
            .done(function(response) {
                if (response.success) {
                    var review = response.data;

                    // Populate edit form
                    $('#edit-comment-id').val(review.comment_id);
                    $('#edit-reviewer-name').text(review.author + ' (' + review.author_email + ')');
                    $('input[name="edit_rating"][value="' + review.rating + '"]').prop('checked', true);
                    if (tinyMCE.get('wcrm-edit-review-text')) {
                        tinyMCE.get('wcrm-edit-review-text').setContent(review.review_text);
                    } else {
                        $('#wcrm-edit-review-text').val(review.review_text);
                    }

                    // Format and set the date for datetime-local input
                    if (review.date) {
                        var dateObj = new Date(review.date);
                        var year = dateObj.getFullYear();
                        var month = String(dateObj.getMonth() + 1).padStart(2, '0');
                        var day = String(dateObj.getDate()).padStart(2, '0');
                        var hours = String(dateObj.getHours()).padStart(2, '0');
                        var minutes = String(dateObj.getMinutes()).padStart(2, '0');
                        var formattedDate = year + '-' + month + '-' + day + 'T' + hours + ':' + minutes;
                        $('#wcrm-edit-review-date').val(formattedDate);
                    }

                    // Show modal
                    $('#wcrm-edit-modal').fadeIn(200);
                } else {
                    alert(response.data);
                }
            })
            .fail(function() {
                alert('An error occurred. Please try again.');
            })
            .always(function() {
                $btn.prop('disabled', false).text(originalText);
            });
        });
    });

    // Edit Review Form Submit
    $('#wcrm-edit-form').on('submit', function(e) {
        e.preventDefault();

        var formData = {
            action: 'wcrm_edit_review',
            security: wcrmData.nonce,
            comment_id: $('#edit-comment-id').val(),
            rating: $('input[name="edit_rating"]:checked').val(),
            review_text: tinyMCE.get('wcrm-edit-review-text') ? tinyMCE.get('wcrm-edit-review-text').getContent() : $('#wcrm-edit-review-text').val(),
            review_date: $('#wcrm-edit-review-date').val()
        };

        var $submitBtn = $(this).find('button[type="submit"]');
        var originalText = $submitBtn.text();
        $submitBtn.prop('disabled', true).text('Queued...');

        // Add to request queue
        wcrmRequestQueue.add(function() {
            $submitBtn.text('Updating...');
            return $.post(wcrmData.ajaxurl, formData)
                .done(function(response) {
                    if (response.success) {
                        // Close modal immediately
                        $('#wcrm-edit-modal').fadeOut(200);

                        // Show success message in reviews list
                        $('#wcrm-reviews-list').prepend('<div class="wcrm-message success" style="margin-bottom: 15px;">' + response.data.message + '</div>');

                        // Reload reviews after a short delay
                        setTimeout(function() {
                            $('#wcrm-load-reviews').click();
                        }, 300);

                        // Remove success message after 3 seconds
                        setTimeout(function() {
                            $('.wcrm-message.success').fadeOut(function() {
                                $(this).remove();
                            });
                        }, 3000);

                        // Reset button
                        $submitBtn.prop('disabled', false).text(originalText);
                    } else {
                        alert(response.data);
                        $submitBtn.prop('disabled', false).text(originalText);
                    }
                })
                .fail(function(jqXHR, textStatus, errorThrown) {
                    console.error('Edit review error:', textStatus, errorThrown);
                    alert('An error occurred while updating the review. Please try again.');
                    $submitBtn.prop('disabled', false).text(originalText);
                });
        });
    });

    // Delete Review Button
    $(document).on('click', '.wcrm-delete-review', function() {
        if (!confirm('Are you sure you want to delete this review? This action cannot be undone.')) {
            return;
        }

        var commentId = $(this).data('comment-id');
        var $reviewItem = $(this).closest('.wcrm-review-item');
        var $btn = $(this);
        $btn.prop('disabled', true).text('Deleting...');

        // Add to request queue
        wcrmRequestQueue.add(function() {
            return $.post(wcrmData.ajaxurl, {
                action: 'wcrm_delete_review',
                security: wcrmData.nonce,
                comment_id: commentId
            })
            .done(function(response) {
                if (response.success) {
                    $reviewItem.fadeOut(300, function() {
                        $(this).remove();

                        // Check if any reviews left
                        if ($('.wcrm-review-item').length === 0) {
                            $('#wcrm-reviews-list').html('<div class="wcrm-empty">No reviews found for this product.</div>');
                        }
                    });
                } else {
                    alert(response.data);
                    $btn.prop('disabled', false).text('Delete');
                }
            })
            .fail(function() {
                alert('An error occurred. Please try again.');
                $btn.prop('disabled', false).text('Delete');
            });
        });
    });

    // Close Modal
    $('.wcrm-modal-close').on('click', function() {
        $('#wcrm-edit-modal').fadeOut(200);
    });

    // Close modal when clicking outside
    $(window).on('click', function(e) {
        if ($(e.target).is('#wcrm-edit-modal')) {
            $('#wcrm-edit-modal').fadeOut(200);
        }
    });

    // Helper function to generate star rating HTML
    function getStarRating(rating) {
        var stars = '';
        for (var i = 1; i <= 5; i++) {
            if (i <= rating) {
                stars += '★';
            } else {
                stars += '☆';
            }
        }
        return stars;
    }

    // Helper function to escape HTML
    function escapeHtml(text) {
        var map = {
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#039;'
        };
        return text.replace(/[&<>"']/g, function(m) { return map[m]; });
    }
});
