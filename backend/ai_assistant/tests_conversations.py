"""Conversation-history API tests (persistent Ask AI sidebar)."""

import uuid
from unittest.mock import patch

from django.core.cache import cache
from django.test import TestCase, override_settings
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole

from . import providers
from .models import Conversation, Message

_PASSWORD = "Str0ng!Pass9"
LIST_URL = "/api/ai-assistant/conversations/"
CHAT_URL = "/api/ai/chat/"


def _user(email=None):
    user = User.objects.create_user(
        email=email or f"conv-{uuid.uuid4().hex[:10]}@example.com",
        password=_PASSWORD,
        first_name="History",
        last_name="Owner",
        account_status="ACTIVE",
    )
    UserRole.objects.create(user=user, role=Role.objects.get(code="PATIENT"))
    return user


def _client(user):
    client = APIClient()
    client.credentials(
        HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}",
    )
    return client


def _detail_url(uid):
    return f"{LIST_URL}{uid}/"


def _messages_url(uid):
    return f"{LIST_URL}{uid}/messages/"


class ConversationAuthTests(TestCase):
    def setUp(self):
        cache.clear()

    def test_anonymous_cannot_list(self):
        self.assertEqual(APIClient().get(LIST_URL).status_code, 401)

    def test_anonymous_cannot_create(self):
        resp = APIClient().post(LIST_URL, {"title": "x"}, format="json")
        self.assertEqual(resp.status_code, 401)


class ConversationCrudTests(TestCase):
    def setUp(self):
        cache.clear()
        self.user = _user()
        self.client = _client(self.user)

    def test_create_with_message_derives_title(self):
        resp = self.client.post(
            LIST_URL, {"message": "What triggers a pain crisis?"}, format="json"
        )
        self.assertEqual(resp.status_code, 201, resp.data)
        self.assertEqual(resp.data["title"], "What triggers a pain crisis?")
        self.assertEqual(resp.data["messages"], [])
        self.assertTrue(Conversation.objects.filter(user=self.user).exists())

    def test_list_is_own_only_and_excludes_archived(self):
        mine = Conversation.objects.create(user=self.user, title="Mine")
        Conversation.objects.create(user=self.user, title="Archived", archived=True)
        other = _user()
        Conversation.objects.create(user=other, title="Theirs")

        resp = self.client.get(LIST_URL)
        self.assertEqual(resp.status_code, 200)
        titles = [row["title"] for row in resp.data]
        self.assertEqual(titles, ["Mine"])
        self.assertEqual(str(mine.uid), resp.data[0]["uid"])

    def test_retrieve_own_conversation_with_messages(self):
        conv = Conversation.objects.create(user=self.user, title="Mine")
        Message.objects.create(
            conversation=conv, role=Message.Role.USER, content="hello"
        )
        resp = self.client.get(_detail_url(conv.uid))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data["messages"]), 1)
        self.assertEqual(resp.data["messages"][0]["content"], "hello")

    def test_other_users_conversation_is_404(self):
        other = _user()
        conv = Conversation.objects.create(user=other, title="Secret")
        self.assertEqual(self.client.get(_detail_url(conv.uid)).status_code, 404)
        self.assertEqual(
            self.client.patch(
                _detail_url(conv.uid), {"title": "hijack"}, format="json"
            ).status_code,
            404,
        )
        self.assertEqual(self.client.delete(_detail_url(conv.uid)).status_code, 404)
        self.assertTrue(Conversation.objects.filter(uid=conv.uid).exists())

    def test_rename(self):
        conv = Conversation.objects.create(user=self.user, title="Old")
        resp = self.client.patch(
            _detail_url(conv.uid), {"title": "New name"}, format="json"
        )
        self.assertEqual(resp.status_code, 200)
        conv.refresh_from_db()
        self.assertEqual(conv.title, "New name")

    def test_delete_cascades_messages(self):
        conv = Conversation.objects.create(user=self.user, title="Bye")
        Message.objects.create(
            conversation=conv, role=Message.Role.USER, content="hi"
        )
        resp = self.client.delete(_detail_url(conv.uid))
        self.assertEqual(resp.status_code, 204)
        self.assertFalse(Conversation.objects.filter(uid=conv.uid).exists())
        self.assertFalse(Message.objects.filter(conversation_id=conv.pk).exists())


class ConversationTurnPersistenceTests(TestCase):
    def setUp(self):
        cache.clear()
        self.user = _user()
        self.client = _client(self.user)

    def test_chat_persists_both_roles_and_returns_conversation_uid(self):
        resp = self.client.post(
            CHAT_URL, {"message": "What is sickle cell disease?"}, format="json"
        )
        self.assertEqual(resp.status_code, 200, resp.data)
        self.assertIn("conversation_uid", resp.data)

        conv = Conversation.objects.get(uid=resp.data["conversation_uid"])
        roles = list(conv.messages.values_list("role", flat=True))
        self.assertEqual(roles, [Message.Role.USER, Message.Role.ASSISTANT])
        assistant = conv.messages.get(role=Message.Role.ASSISTANT)
        self.assertEqual(assistant.content, resp.data["message"])

    def test_second_turn_reuses_conversation_and_sends_history(self):
        first = self.client.post(
            CHAT_URL, {"message": "What is sickle cell disease?"}, format="json"
        )
        conv_uid = first.data["conversation_uid"]
        second = self.client.post(
            CHAT_URL,
            {
                "message": "What foods help?",
                "conversation_uid": conv_uid,
            },
            format="json",
        )
        self.assertEqual(second.status_code, 200, second.data)
        self.assertEqual(second.data["conversation_uid"], conv_uid)

        conv = Conversation.objects.get(uid=conv_uid)
        self.assertEqual(conv.messages.count(), 4)

    def test_messages_action_appends_to_existing_conversation(self):
        conv = Conversation.objects.create(user=self.user, title="Existing")
        Message.objects.create(
            conversation=conv, role=Message.Role.USER, content="earlier question"
        )
        Message.objects.create(
            conversation=conv, role=Message.Role.ASSISTANT, content="earlier answer"
        )
        resp = self.client.post(
            _messages_url(conv.uid),
            {"message": "What is sickle cell disease?"},
            format="json",
        )
        self.assertEqual(resp.status_code, 200, resp.data)
        self.assertEqual(resp.data["conversation_uid"], str(conv.uid))
        self.assertEqual(conv.messages.count(), 4)

    def test_cannot_post_message_to_another_users_conversation(self):
        other = _user()
        conv = Conversation.objects.create(user=other, title="Theirs")
        resp = self.client.post(
            _messages_url(conv.uid),
            {"message": "What is sickle cell disease?"},
            format="json",
        )
        self.assertEqual(resp.status_code, 404)
        self.assertEqual(conv.messages.count(), 0)

    @override_settings(AI_PROVIDER="gemini", GEMINI_API_KEY="")
    def test_provider_failure_leaves_no_partial_turn(self):
        resp = self.client.post(
            CHAT_URL, {"message": "What is sickle cell disease?"}, format="json"
        )
        self.assertEqual(resp.status_code, 503)
        self.assertFalse(Conversation.objects.filter(user=self.user).exists())
        self.assertFalse(Message.objects.exists())

    def test_assistant_meta_preserves_emergency_and_safety_envelope(self):
        resp = self.client.post(
            CHAT_URL, {"message": "Severe chest pain now"}, format="json"
        )
        self.assertEqual(resp.status_code, 200, resp.data)
        conv = Conversation.objects.get(uid=resp.data["conversation_uid"])
        assistant = conv.messages.get(role=Message.Role.ASSISTANT)
        self.assertTrue(assistant.meta["emergency_action"])
        self.assertTrue(assistant.meta["safety"]["blocked"])
        self.assertEqual(
            assistant.meta["emergency_categories"],
            resp.data["emergency_categories"],
        )

        detail = self.client.get(_detail_url(conv.uid))
        self.assertEqual(detail.status_code, 200)
        restored = [
            m for m in detail.data["messages"] if m["role"] == Message.Role.ASSISTANT
        ][0]
        self.assertTrue(restored["meta"]["emergency_action"])

    def test_history_uses_recent_window_and_excludes_current_turn(self):
        conv = Conversation.objects.create(user=self.user, title="Long")
        for i in range(55):
            Message.objects.create(
                conversation=conv, role=Message.Role.USER, content=f"q{i}"
            )
            Message.objects.create(
                conversation=conv, role=Message.Role.ASSISTANT, content=f"a{i}"
            )

        captured = {}

        class _FakeProvider:
            def generate(self, payload):
                captured["history"] = payload.history
                return providers.AIResult(text="answer")

        with patch(
            "ai_assistant.providers.get_ai_provider",
            return_value=_FakeProvider(),
        ):
            resp = self.client.post(
                CHAT_URL,
                {
                    "message": "What is sickle cell disease?",
                    "conversation_uid": str(conv.uid),
                },
                format="json",
            )

        self.assertEqual(resp.status_code, 200, resp.data)
        history = captured["history"]
        self.assertLessEqual(len(history), 50)
        contents = [h["content"] for h in history]
        self.assertNotIn("What is sickle cell disease?", contents)
        self.assertEqual(contents[-1], "a54")
        self.assertEqual(contents[0], "q30")

    def test_list_is_not_limited_by_the_chat_budget(self):
        # The client refreshes the sidebar after each turn; if conversation
        # reads shared the 6/min chat bucket the usable rate would be halved.
        for _ in range(6):
            resp = self.client.post(
                CHAT_URL, {"message": "What is sickle cell disease?"}, format="json"
            )
            self.assertEqual(resp.status_code, 200, resp.data)
        self.assertEqual(self.client.get(LIST_URL).status_code, 200)

    @override_settings(AI_PROVIDER="gemini", GEMINI_API_KEY="")
    def test_provider_failure_in_existing_conversation_rolls_back_user_turn(self):
        conv = Conversation.objects.create(user=self.user, title="Existing")
        resp = self.client.post(
            _messages_url(conv.uid),
            {"message": "What is sickle cell disease?"},
            format="json",
        )
        self.assertEqual(resp.status_code, 503)
        self.assertTrue(Conversation.objects.filter(uid=conv.uid).exists())
        self.assertEqual(conv.messages.count(), 0)
