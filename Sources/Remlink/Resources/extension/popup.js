const HOST_NAME = "com.landlord.remlink";

const pageTitle = document.getElementById("pageTitle");
const titleInput = document.getElementById("title");
const noteInput = document.getElementById("note");
const tagsInput = document.getElementById("tags");
const tagSuggestions = document.getElementById("tagSuggestions");
const saveButton = document.getElementById("saveButton");
const statusEl = document.getElementById("status");

let activeTab = null;
let availableTags = [];
let selectedSuggestionIndex = -1;
let tagsLoaded = false;

function setStatus(message, isError = false) {
  statusEl.textContent = message;
  statusEl.classList.toggle("error", isError);
}

function parseTags(value) {
  return value
    .split(/[,\s，、]+/)
    .map((tag) => tag.trim().replace(/^#/, ""))
    .filter(Boolean);
}

function currentTagFragment() {
  const value = tagsInput.value;
  const cursor = tagsInput.selectionStart ?? value.length;
  const beforeCursor = value.slice(0, cursor);
  const separatorIndex = Math.max(
    beforeCursor.lastIndexOf(","),
    beforeCursor.lastIndexOf("，"),
    beforeCursor.lastIndexOf("、"),
    beforeCursor.lastIndexOf(" ")
  );
  const start = separatorIndex + 1;
  return {
    start,
    end: cursor,
    query: value.slice(start, cursor).trim().replace(/^#/, "")
  };
}

function selectedExistingTagsOutsideCurrentFragment() {
  const value = tagsInput.value;
  const { start, end } = currentTagFragment();
  const outsideCurrentFragment = `${value.slice(0, start)} ${value.slice(end)}`;
  return new Set(parseTags(outsideCurrentFragment).map((tag) => tag.toLocaleLowerCase()));
}

function filteredSuggestions() {
  const { query } = currentTagFragment();
  const normalizedQuery = query.toLocaleLowerCase();
  const selected = selectedExistingTagsOutsideCurrentFragment();
  const matches = availableTags.filter((tag) => {
    const normalizedTag = tag.toLocaleLowerCase();
    return normalizedTag.includes(normalizedQuery) && !selected.has(normalizedTag);
  });

  if (query && !availableTags.some((tag) => tag.toLocaleLowerCase() === normalizedQuery)) {
    matches.push({ create: true, value: query });
  }
  return matches;
}

function renderTagSuggestions() {
  const suggestions = filteredSuggestions();
  tagSuggestions.textContent = "";

  if (!suggestions.length) {
    const empty = document.createElement("div");
    empty.className = "tag-option empty";
    empty.textContent = tagsLoaded ? "没有匹配的已有标签" : "读取标签中...";
    tagSuggestions.append(empty);
    selectedSuggestionIndex = -1;
    tagSuggestions.hidden = false;
    return;
  }

  selectedSuggestionIndex = Math.min(
    Math.max(selectedSuggestionIndex, 0),
    suggestions.length - 1
  );

  suggestions.forEach((suggestion, index) => {
    const option = document.createElement("div");
    const isCreate = typeof suggestion === "object";
    const value = isCreate ? suggestion.value : suggestion;
    option.className = `tag-option${isCreate ? " create" : ""}`;
    option.setAttribute("role", "option");
    option.setAttribute("aria-selected", String(index === selectedSuggestionIndex));
    option.dataset.value = value;
    option.textContent = isCreate ? `创建新标签：${value}` : value;
    option.addEventListener("mousedown", (event) => {
      event.preventDefault();
      applyTagSuggestion(value);
    });
    tagSuggestions.append(option);
  });

  tagSuggestions.hidden = false;
}

function closeTagSuggestions() {
  tagSuggestions.hidden = true;
  selectedSuggestionIndex = -1;
}

function applyTagSuggestion(tag) {
  const value = tagsInput.value;
  const { start, end } = currentTagFragment();
  const prefix = value.slice(0, start).replace(/\s+$/, "");
  const suffix = value.slice(end).replace(/^[,\s，、]+/, "");
  const before = prefix ? `${prefix}, ` : "";
  const after = suffix ? `, ${suffix}` : "";
  tagsInput.value = `${before}${tag}${after}`;
  const cursor = before.length + tag.length;
  tagsInput.setSelectionRange(cursor, cursor);
  closeTagSuggestions();
  tagsInput.focus();
}

async function loadAvailableTags() {
  if (tagsLoaded) return;
  try {
    const response = await sendNativeMessage({ action: "list_tags", filter: "链接" });
    availableTags = Array.isArray(response.tags) ? response.tags : [];
  } catch (error) {
    setStatus(error.message, true);
    availableTags = [];
  } finally {
    tagsLoaded = true;
    if (document.activeElement === tagsInput) {
      selectedSuggestionIndex = 0;
      renderTagSuggestions();
    }
  }
}

async function getActiveTab() {
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  return tabs[0] || null;
}

async function restoreDraft(url) {
  const key = `draft:${url}`;
  const stored = await chrome.storage.local.get(key);
  const draft = stored[key];
  if (!draft) return;
  titleInput.value = draft.title || titleInput.value;
  noteInput.value = draft.note || "";
  tagsInput.value = draft.tags || "";
}

async function saveDraft(url) {
  const key = `draft:${url}`;
  await chrome.storage.local.set({
    [key]: {
      title: titleInput.value,
      note: noteInput.value,
      tags: tagsInput.value
    }
  });
}

function sendNativeMessage(payload) {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendNativeMessage(HOST_NAME, payload, (response) => {
      const error = chrome.runtime.lastError;
      if (error) {
        reject(new Error(error.message));
        return;
      }
      if (!response || response.ok !== true) {
        reject(new Error(response?.error || "保存失败"));
        return;
      }
      resolve(response);
    });
  });
}

async function saveCurrentPage() {
  if (!activeTab?.url) {
    setStatus("没有可保存的当前页面", true);
    return;
  }

  saveButton.disabled = true;
  setStatus("保存中...");

  try {
    await saveDraft(activeTab.url);
    await sendNativeMessage({
      action: "save_link",
      title: titleInput.value.trim() || activeTab.title || activeTab.url,
      url: activeTab.url,
      note: noteInput.value.trim(),
      tags: parseTags(tagsInput.value)
    });
    setStatus("已保存");
    window.setTimeout(() => window.close(), 550);
  } catch (error) {
    setStatus(error.message, true);
  } finally {
    saveButton.disabled = false;
  }
}

document.addEventListener("DOMContentLoaded", async () => {
  activeTab = await getActiveTab();
  if (!activeTab?.url) {
    pageTitle.textContent = "无法读取当前网页";
    saveButton.disabled = true;
    return;
  }
  titleInput.value = activeTab.title || activeTab.url;
  pageTitle.textContent = activeTab.url;
  await restoreDraft(activeTab.url);
  titleInput.focus();
  titleInput.select();
});

saveButton.addEventListener("click", saveCurrentPage);

tagsInput.addEventListener("focus", () => {
  selectedSuggestionIndex = 0;
  renderTagSuggestions();
  loadAvailableTags();
});

tagsInput.addEventListener("click", () => {
  selectedSuggestionIndex = 0;
  renderTagSuggestions();
  loadAvailableTags();
});

tagsInput.addEventListener("input", () => {
  selectedSuggestionIndex = 0;
  renderTagSuggestions();
});

tagsInput.addEventListener("keydown", (event) => {
  if (tagSuggestions.hidden) return;
  const suggestions = filteredSuggestions();
  if (event.key === "ArrowDown") {
    event.preventDefault();
    selectedSuggestionIndex = suggestions.length
      ? (selectedSuggestionIndex + 1) % suggestions.length
      : -1;
    renderTagSuggestions();
  } else if (event.key === "ArrowUp") {
    event.preventDefault();
    selectedSuggestionIndex = suggestions.length
      ? (selectedSuggestionIndex - 1 + suggestions.length) % suggestions.length
      : -1;
    renderTagSuggestions();
  } else if (event.key === "Enter" && selectedSuggestionIndex >= 0) {
    event.preventDefault();
    const suggestion = suggestions[selectedSuggestionIndex];
    const value = typeof suggestion === "object" ? suggestion.value : suggestion;
    applyTagSuggestion(value);
  } else if (event.key === "Escape") {
    closeTagSuggestions();
  }
});

document.addEventListener("mousedown", (event) => {
  if (!tagSuggestions.contains(event.target) && event.target !== tagsInput) {
    closeTagSuggestions();
  }
});

document.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
    event.preventDefault();
    saveCurrentPage();
  }
});
