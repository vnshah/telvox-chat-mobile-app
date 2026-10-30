# Mobile API endpoint inventory

Generated from the bundled collection on 30 October 2026. 107 requests.

| Folder | Request | Method | URL |
| --- | --- | --- | --- |
| 1. Authentication | Login | POST | {{base_url}}/api/mobile/v1/auth/login |
| 1. Authentication | Verify second factor | POST | {{base_url}}/api/mobile/v1/auth/two-factor |
| 1. Authentication | Resend second-factor code | POST | {{base_url}}/api/mobile/v1/auth/two-factor/resend |
| 1. Authentication | Rotate token | POST | {{base_url}}/api/mobile/v1/auth/token/rotate |
| 1. Authentication | Logout | POST | {{base_url}}/api/mobile/v1/auth/logout |
| 2. Account & number picker | Me | GET | {{base_url}}/api/mobile/v1/me |
| 2. Account & number picker | Businesses | GET | {{base_url}}/api/mobile/v1/businesses?search=&page=1 |
| 2. Account & number picker | Numbers of a business | GET | {{base_url}}/api/mobile/v1/numbers?business_user_id={{business_user_id}} |
| 2. Account & number picker | Inbox config | GET | {{base_url}}/api/mobile/v1/config |
| 2. Account & number picker | Presence heartbeat | POST | {{base_url}}/api/mobile/v1/presence/heartbeat |
| 2. Account & number picker | My devices | GET | {{base_url}}/api/mobile/v1/me/devices |
| 2. Account & number picker | Sign out one of my devices | DELETE | {{base_url}}/api/mobile/v1/me/devices/:device |
| 3. Realtime | Authorise a private channel | POST | {{base_url}}/api/mobile/v1/broadcasting/auth |
| 4. Inbox / AI assist | AI: fill custom fields from the conversation | POST | {{base_url}}/api/mobile/v1/inbox/ai/extract-fields |
| 4. Inbox / AI assist | AI: draft a reply | POST | {{base_url}}/api/mobile/v1/inbox/ai/generate-reply |
| 4. Inbox / AI assist | AI: rewrite a draft | POST | {{base_url}}/api/mobile/v1/inbox/ai/rewrite |
| 4. Inbox / AI assist | AI: suggest templates | POST | {{base_url}}/api/mobile/v1/inbox/ai/suggest-template |
| 4. Inbox / AI assist | AI: summarise a conversation | POST | {{base_url}}/api/mobile/v1/inbox/ai/summarize |
| 4. Inbox / AI assist | AI: latest stored summary | POST | {{base_url}}/api/mobile/v1/inbox/ai/summarize/latest |
| 4. Inbox / AI assist | AI: fill template variables | POST | {{base_url}}/api/mobile/v1/inbox/ai/template-variables |
| 4. Inbox / AI assist | AI: translate a message | POST | {{base_url}}/api/mobile/v1/inbox/ai/translate |
| 4. Inbox / Canned responses | List canned responses | GET | {{base_url}}/api/mobile/v1/inbox/canned-responses |
| 4. Inbox / Canned responses | Search canned responses | GET | {{base_url}}/api/mobile/v1/inbox/canned-responses/search?q=delay |
| 4. Inbox / Catalogue | List catalogues | GET | {{base_url}}/api/mobile/v1/inbox/get-catalogues |
| 4. Inbox / Catalogue | List products of a catalogue | GET | {{base_url}}/api/mobile/v1/inbox/get-products?catalogue_id=3 |
| 4. Inbox / Contact actions | Assign / unassign a contact | POST | {{base_url}}/api/mobile/v1/inbox/contacts/:contactId/assign |
| 4. Inbox / Contact actions | Block contact on WhatsApp | POST | {{base_url}}/api/mobile/v1/inbox/contacts/:contactId/block |
| 4. Inbox / Contact actions | Unblock contact on WhatsApp | DELETE | {{base_url}}/api/mobile/v1/inbox/contacts/:contactId/block |
| 4. Inbox / Contact actions | Add contact to DND list | POST | {{base_url}}/api/mobile/v1/inbox/contacts/:contactId/dnd |
| 4. Inbox / Contact actions | Remove contact from DND list | DELETE | {{base_url}}/api/mobile/v1/inbox/contacts/:contactId/dnd |
| 4. Inbox / Contact actions | Export chat transcript (CSV) | GET | {{base_url}}/api/mobile/v1/inbox/contacts/:contactId/export |
| 4. Inbox / Contact actions | Toggle favourite (star) for me | POST | {{base_url}}/api/mobile/v1/inbox/contacts/:contactId/favorite |
| 4. Inbox / Contact actions | Update contact profile | POST | {{base_url}}/api/mobile/v1/inbox/contacts/:contactId/profile |
| 4. Inbox / Contact custom fields | Get a contact's custom fields and values | GET | {{base_url}}/api/mobile/v1/inbox/custom-fields?contact_id=101 |
| 4. Inbox / Contact custom fields | Set a contact's custom field value | POST | {{base_url}}/api/mobile/v1/inbox/custom-fields/update |
| 4. Inbox / Contact notes | List a contact's notes | GET | {{base_url}}/api/mobile/v1/inbox/notes?contact_id=101 |
| 4. Inbox / Contact notes | Add or update a contact note | POST | {{base_url}}/api/mobile/v1/inbox/notes |
| 4. Inbox / Contact notes | Delete a contact note | DELETE | {{base_url}}/api/mobile/v1/inbox/notes/:noteId |
| 4. Inbox / Contact tags | Attach a tag to a contact | POST | {{base_url}}/api/mobile/v1/inbox/contacts/tag/add |
| 4. Inbox / Contact tags | Detach a tag from a contact | POST | {{base_url}}/api/mobile/v1/inbox/contacts/tag/remove |
| 4. Inbox / Contact tags | List tags | GET | {{base_url}}/api/mobile/v1/inbox/tags?contact_id=101 |
| 4. Inbox / Contact tags | Create or rename a tag | POST | {{base_url}}/api/mobile/v1/inbox/tags/add |
| 4. Inbox / Contacts | List contacts (conversation list) | POST | {{base_url}}/api/mobile/v1/inbox/contacts |
| 4. Inbox / Contacts | Count contacts | POST | {{base_url}}/api/mobile/v1/inbox/contacts/total |
| 4. Inbox / Contacts | Get contact details | POST | {{base_url}}/api/mobile/v1/inbox/getContactDetails |
| 4. Inbox / Conversations | Mark conversation as no longer on screen | POST | {{base_url}}/api/mobile/v1/inbox/contacts/:contactId/close |
| 4. Inbox / Conversations | Mark conversation as on screen | POST | {{base_url}}/api/mobile/v1/inbox/contacts/:contactId/open |
| 4. Inbox / Conversations | Close conversation | POST | {{base_url}}/api/mobile/v1/inbox/conversation/close |
| 4. Inbox / Conversations | Focus conversation (switch chats) | POST | {{base_url}}/api/mobile/v1/inbox/conversation/focus |
| 4. Inbox / Conversations | Reopen conversation | POST | {{base_url}}/api/mobile/v1/inbox/conversation/reopen |
| 4. Inbox / Conversations | Unread message count (badge) | GET | {{base_url}}/api/mobile/v1/inbox/unread-count |
| 4. Inbox / Custom fields | Delete a file custom-field value | POST | {{base_url}}/api/mobile/v1/inbox/deleteFile |
| 4. Inbox / Custom fields | Get custom field values | POST | {{base_url}}/api/mobile/v1/inbox/getCustomFieldValues |
| 4. Inbox / Custom fields | Get custom field definitions | POST | {{base_url}}/api/mobile/v1/inbox/getCustomFields |
| 4. Inbox / Custom fields | Store date value | POST | {{base_url}}/api/mobile/v1/inbox/storeDateValue |
| 4. Inbox / Custom fields | Store multi-select value | POST | {{base_url}}/api/mobile/v1/inbox/storeMultiValue |
| 4. Inbox / Custom fields | Store single-select value | POST | {{base_url}}/api/mobile/v1/inbox/storeSingleValue |
| 4. Inbox / Custom fields | Store text value | POST | {{base_url}}/api/mobile/v1/inbox/storeTextValue |
| 4. Inbox / Custom fields | Store textarea value | POST | {{base_url}}/api/mobile/v1/inbox/storeTextareaValue |
| 4. Inbox / Custom fields | Store several custom field values (batch) | POST | {{base_url}}/api/mobile/v1/inbox/storeCustomFieldValues |
| 4. Inbox / Custom fields | Upload file custom-field value | POST | {{base_url}}/api/mobile/v1/inbox/storeFileValue |
| 4. Inbox / Dispositions | List dispositions | GET | {{base_url}}/api/mobile/v1/inbox/tickets/:ticketId/dispositions |
| 4. Inbox / Dispositions | Set ticket disposition | POST | {{base_url}}/api/mobile/v1/inbox/tickets/:ticketId/disposition |
| 4. Inbox / Media | Get shared media / docs / links | POST | {{base_url}}/api/mobile/v1/inbox/getMediaData |
| 4. Inbox / Media | Get images & videos (gallery) | POST | {{base_url}}/api/mobile/v1/inbox/getMedias |
| 4. Inbox / Media | Contact media gallery | GET | {{base_url}}/api/mobile/v1/inbox/media-gallery?contact_id=101&type=media&search=invoice |
| 4. Inbox / Media | Upload a media file | POST | {{base_url}}/api/mobile/v1/inbox/media/upload |
| 4. Inbox / Messages | Get conversation messages (paged) | POST | {{base_url}}/api/mobile/v1/inbox/messages |
| 4. Inbox / Messages | Count conversation messages | POST | {{base_url}}/api/mobile/v1/inbox/messages/total |
| 4. Inbox / New contact | Create a new contact | POST | {{base_url}}/api/mobile/v1/inbox/contact/new |
| 4. Inbox / Reactions | React to a message | POST | {{base_url}}/api/mobile/v1/inbox/reactions |
| 4. Inbox / Reactions | Remove reaction | DELETE | {{base_url}}/api/mobile/v1/inbox/reactions |
| 4. Inbox / Send messages | Send a message | POST | {{base_url}}/api/mobile/v1/inbox/send |
| 4. Inbox / Templates | List sendable templates | GET | {{base_url}}/api/mobile/v1/inbox/templates?contact_id=101 |
| 4. Inbox / Templates | Get a template | GET | {{base_url}}/api/mobile/v1/inbox/templates/:templateId |
| 4. Inbox / Templates | Send a template to a contact | POST | {{base_url}}/api/mobile/v1/inbox/send-template-by-contact |
| 4. Inbox / Ticket actions | Assign ticket | POST | {{base_url}}/api/mobile/v1/inbox/tickets/:ticketId/assign |
| 4. Inbox / Ticket actions | Update ticket status | POST | {{base_url}}/api/mobile/v1/inbox/tickets/:ticketId/status |
| 4. Inbox / Ticket actions | Update ticket priority | POST | {{base_url}}/api/mobile/v1/inbox/tickets/:ticketId/priority |
| 4. Inbox / Ticket actions | Update ticket subject | POST | {{base_url}}/api/mobile/v1/inbox/tickets/:ticketId/subject |
| 4. Inbox / Ticket actions | Mark ticket as seen | POST | {{base_url}}/api/mobile/v1/inbox/tickets/:ticketId/mark-seen |
| 4. Inbox / Ticket actions | Mark ticket open in a viewer | POST | {{base_url}}/api/mobile/v1/inbox/tickets/:ticketId/open |
| 4. Inbox / Ticket actions | Mark ticket closed in a viewer | POST | {{base_url}}/api/mobile/v1/inbox/tickets/:ticketId/close |
| 4. Inbox / Ticket actions | Split ticket | POST | {{base_url}}/api/mobile/v1/inbox/tickets/:ticketId/split |
| 4. Inbox / Ticket media | List ticket media | GET | {{base_url}}/api/mobile/v1/inbox/tickets/:ticketId/media?return=1 |
| 4. Inbox / Ticket media | Get ticket media by type | POST | {{base_url}}/api/mobile/v1/inbox/tickets/:ticketId/media-data |
| 4. Inbox / Ticket notes | List ticket notes | GET | {{base_url}}/api/mobile/v1/inbox/ticket/:ticketId/notes |
| 4. Inbox / Ticket notes | Add ticket note | POST | {{base_url}}/api/mobile/v1/inbox/ticket/:ticketId/notes |
| 4. Inbox / Ticket notes | Update ticket note | PUT | {{base_url}}/api/mobile/v1/inbox/ticket/:ticketId/notes/:noteId |
| 4. Inbox / Ticket notes | Delete ticket note | DELETE | {{base_url}}/api/mobile/v1/inbox/ticket/:ticketId/notes/:noteId |
| 4. Inbox / Ticket tags | List tags for filtering | GET | {{base_url}}/api/mobile/v1/inbox/ticket_tags |
| 4. Inbox / Ticket tags | List ticket tags | GET | {{base_url}}/api/mobile/v1/inbox/tickets/:ticketId/tags |
| 4. Inbox / Ticket tags | List tags not on the ticket | GET | {{base_url}}/api/mobile/v1/inbox/tickets/:ticketId/unattached-tags |
| 4. Inbox / Ticket tags | Attach tag to ticket | POST | {{base_url}}/api/mobile/v1/inbox/tickets/:ticketId/tags/:tagId |
| 4. Inbox / Ticket tags | Remove tag from ticket | DELETE | {{base_url}}/api/mobile/v1/inbox/tickets/:ticketId/tags/:tagId |
| 4. Inbox / Tickets | List tickets | POST | {{base_url}}/api/mobile/v1/inbox/tickets |
| 4. Inbox / Tickets | Get ticket messages | POST | {{base_url}}/api/mobile/v1/inbox/ticket_messages |
| 4. Inbox / Tickets | Get ticket details | POST | {{base_url}}/api/mobile/v1/inbox/ticket_details |
| 4. Inbox / Tickets | Get ticket metadata (statuses & priorities) | GET | {{base_url}}/api/mobile/v1/inbox/ticket_metadata?ticket_id=101 |
| 4. Inbox / Tickets | Create ticket | POST | {{base_url}}/api/mobile/v1/inbox/ticket_create |
| 4. Inbox / Tickets | Get create-ticket form metadata | GET | {{base_url}}/api/mobile/v1/inbox/ticket_create_metadata |
| 4. Inbox / Tickets | Search contacts for a new ticket | GET | {{base_url}}/api/mobile/v1/inbox/ticket_search_contacts?search=Rahul&limit=20 |
| 4. Inbox / Tickets | Create contact for a new ticket | POST | {{base_url}}/api/mobile/v1/inbox/ticket_create_contact |
| 4. Inbox / Typing & read | Mark a conversation as read | POST | {{base_url}}/api/mobile/v1/inbox/mark-read |
| 4. Inbox / Typing & read | Send typing indicator | POST | {{base_url}}/api/mobile/v1/inbox/typing |
| 4. Inbox / Users & lookups | List countries | GET | {{base_url}}/api/mobile/v1/inbox/getCountries |
| 4. Inbox / Users & lookups | List assignable users (filter) | GET | {{base_url}}/api/mobile/v1/inbox/users |
