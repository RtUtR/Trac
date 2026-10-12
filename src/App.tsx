/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState } from 'react';
import {
  Copy,
  Check,
  Download,
  FileCode,
  FolderTree,
  Sun,
  Moon,
  Globe,
} from 'lucide-react';
import {
  DELIVERABLE_FILES,
  FOLDER_STRUCTURE_TREE,
  DeliverableFile,
} from './data/deliverables';
import {
  FamilyTrackSimulator,
  AppLang,
} from './components/FamilyTrackSimulator';

type ActiveSection = 'simulator' | 'dart' | 'platform' | 'setup';

export default function App() {
  const [activeSection, setActiveSection] =
    useState<ActiveSection>('simulator');
  const [selectedFileId, setSelectedFileId] = useState<string>('app-config');
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [isDark, setIsDark] = useState<boolean>(false);
  const [lang, setLang] = useState<AppLang>('en');

  const selectedFile: DeliverableFile =
    DELIVERABLE_FILES.find((f) => f.id === selectedFileId) ??
    DELIVERABLE_FILES[0];

  const handleCopy = async (text: string, id: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopiedId(id);
      setTimeout(() => setCopiedId(null), 1800);
    } catch (_) {}
  };

  const handleDownloadFile = (file: DeliverableFile) => {
    const blob = new Blob([file.content], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = file.path.split('/').pop() || file.id;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  const handleDownloadAllBundle = () => {
    const bundleContent = [
      '# ============================================================================',
      '# FamilyTrack — Complete Flutter Project Bundle (iOS + Android)',
      '# ============================================================================',
      '',
      '## Project Folder Structure',
      '```',
      FOLDER_STRUCTURE_TREE,
      '```',
      '',
      ...DELIVERABLE_FILES.map(
        (f) =>
          `\n\n# FILE: ${f.path}\n# Summary: ${f.summary}\n\`\`\`${f.language}\n${f.content}\n\`\`\``
      ),
    ].join('\n');

    const blob = new Blob([bundleContent], {
      type: 'text/markdown;charset=utf-8',
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'FamilyTrack_Flutter_Project_Bundle.md';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  const openDeliverableFile = (fileId: string) => {
    const target = DELIVERABLE_FILES.find((f) => f.id === fileId);
    if (!target) return;
    setSelectedFileId(target.id);
    if (target.category === 'setup') {
      setActiveSection('setup');
    } else if (target.category === 'platform') {
      setActiveSection('platform');
    } else {
      setActiveSection('dart');
    }
  };

  const filteredFiles = DELIVERABLE_FILES.filter((f) => {
    if (activeSection === 'setup') return f.category === 'setup';
    if (activeSection === 'platform') return f.category === 'platform';
    return f.category === 'dart';
  });

  return (
    <div className={isDark ? 'dark' : ''}>
      <div className="min-h-screen bg-neutral-50 dark:bg-neutral-950 text-neutral-950 dark:text-neutral-100 transition-colors">
        {/* Strict 3-Zone Top Bar Contract */}
        <header className="flex items-center justify-between gap-8 px-6 py-4 border-b border-neutral-200 dark:border-neutral-800 bg-white dark:bg-neutral-950">
          {/* Zone 1: Single text element wordmark */}
          <a
            href="#top"
            onClick={(e) => {
              e.preventDefault();
              setActiveSection('simulator');
            }}
            className="text-lg font-bold tracking-tight whitespace-nowrap shrink-0"
          >
            FamilyTrack
          </a>

          {/* Zone 2: 4 concise single-line text navigation links */}
          <nav className="hidden md:flex items-center gap-6 text-sm font-medium text-neutral-600 dark:text-neutral-400">
            <button
              onClick={() => setActiveSection('simulator')}
              className={`hover:text-neutral-950 dark:hover:text-white transition-colors whitespace-nowrap shrink-0 cursor-pointer ${
                activeSection === 'simulator'
                  ? 'text-neutral-950 dark:text-white underline underline-offset-8'
                  : ''
              }`}
            >
              Interactive App
            </button>
            <button
              onClick={() => {
                setSelectedFileId('app-config');
                setActiveSection('dart');
              }}
              className={`hover:text-neutral-950 dark:hover:text-white transition-colors whitespace-nowrap shrink-0 cursor-pointer ${
                activeSection === 'dart'
                  ? 'text-neutral-950 dark:text-white underline underline-offset-8'
                  : ''
              }`}
            >
              Dart Source
            </button>
            <button
              onClick={() => {
                setSelectedFileId('pubspec');
                setActiveSection('platform');
              }}
              className={`hover:text-neutral-950 dark:hover:text-white transition-colors whitespace-nowrap shrink-0 cursor-pointer ${
                activeSection === 'platform'
                  ? 'text-neutral-950 dark:text-white underline underline-offset-8'
                  : ''
              }`}
            >
              Android &amp; iOS
            </button>
            <button
              onClick={() => {
                setSelectedFileId('setup-guide');
                setActiveSection('setup');
              }}
              className={`hover:text-neutral-950 dark:hover:text-white transition-colors whitespace-nowrap shrink-0 cursor-pointer ${
                activeSection === 'setup'
                  ? 'text-neutral-950 dark:text-white underline underline-offset-8'
                  : ''
              }`}
            >
              Setup Guide
            </button>
          </nav>

          {/* Zone 3: 1 primary action */}
          <div className="flex items-center shrink-0">
            <button
              onClick={handleDownloadAllBundle}
              className="px-4 py-2 text-xs font-semibold text-white bg-neutral-950 dark:bg-white dark:text-neutral-950 rounded-lg hover:opacity-90 transition-opacity whitespace-nowrap shrink-0 cursor-pointer"
            >
              Download Flutter Project
            </button>
          </div>
        </header>

        {/* Workspace Toolbar below the header */}
        <div className="border-b border-neutral-200 dark:border-neutral-800 bg-white/70 dark:bg-neutral-900/50 px-6 py-3">
          <div className="max-w-7xl mx-auto flex flex-wrap items-center justify-between gap-4">
            <div className="flex flex-wrap items-center gap-2 text-xs text-neutral-600 dark:text-neutral-400">
              <span>Flutter App (iOS + Android)</span>
              <span aria-hidden="true">·</span>
              <span>MapLibre + Waymorphic Tiles</span>
              <span aria-hidden="true">·</span>
              <span>--dart-define-from-file=config/env.json</span>
            </div>

            <div className="flex items-center gap-2">
              <div className="flex md:hidden items-center gap-1">
                {(
                  [
                    ['simulator', 'App'],
                    ['dart', 'Dart'],
                    ['platform', 'Platform'],
                    ['setup', 'Setup'],
                  ] as Array<[ActiveSection, string]>
                ).map(([sec, lbl]) => (
                  <button
                    key={sec}
                    onClick={() => setActiveSection(sec)}
                    className={`px-2.5 py-1 rounded text-xs font-medium ${
                      activeSection === sec
                        ? 'bg-neutral-950 text-white dark:bg-white dark:text-neutral-950'
                        : 'text-neutral-600 dark:text-neutral-400'
                    }`}
                  >
                    {lbl}
                  </button>
                ))}
              </div>

              <button
                onClick={() => setLang((l) => (l === 'en' ? 'fa' : 'en'))}
                className="px-3 py-1.5 rounded-lg border border-neutral-300 dark:border-neutral-700 text-xs font-medium flex items-center gap-1.5 hover:bg-neutral-100 dark:hover:bg-neutral-800 transition-colors whitespace-nowrap shrink-0 cursor-pointer"
              >
                <Globe className="w-3.5 h-3.5" />
                <span>
                  {lang === 'en'
                    ? 'Language: English (LTR)'
                    : 'زبان: فارسی (RTL)'}
                </span>
              </button>

              <button
                onClick={() => setIsDark((d) => !d)}
                className="px-3 py-1.5 rounded-lg border border-neutral-300 dark:border-neutral-700 text-xs font-medium flex items-center gap-1.5 hover:bg-neutral-100 dark:hover:bg-neutral-800 transition-colors whitespace-nowrap shrink-0 cursor-pointer"
              >
                {isDark ? (
                  <>
                    <Sun className="w-3.5 h-3.5" />
                    <span>Light UI</span>
                  </>
                ) : (
                  <>
                    <Moon className="w-3.5 h-3.5" />
                    <span>Dark UI</span>
                  </>
                )}
              </button>
            </div>
          </div>
        </div>

        {/* Main Workspace Container */}
        <main className="max-w-7xl mx-auto px-6 py-8">
          {activeSection === 'simulator' ? (
            <FamilyTrackSimulator
              isDark={isDark}
              lang={lang}
              onSelectDeliverable={openDeliverableFile}
            />
          ) : (
            <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-start">
              {/* Left Sidebar: Deliverable File Explorer & Folder Structure */}
              <div className="lg:col-span-4 space-y-6">
                <div className="p-5 rounded-2xl border border-neutral-200 dark:border-neutral-800 bg-white dark:bg-neutral-900/40 space-y-3">
                  <div className="flex items-center justify-between">
                    <h2 className="text-sm font-bold flex items-center gap-2">
                      <FileCode className="w-4 h-4" />
                      <span>
                        {activeSection === 'dart'
                          ? 'Flutter Dart Source (lib/)'
                          : activeSection === 'platform'
                          ? 'Android, iOS & Config Files'
                          : 'Setup & Build Guide'}
                      </span>
                    </h2>
                    <span className="text-xs font-mono text-neutral-500">
                      {filteredFiles.length} files
                    </span>
                  </div>

                  <div className="space-y-1.5">
                    {filteredFiles.map((file) => {
                      const active = file.id === selectedFile.id;
                      return (
                        <button
                          key={file.id}
                          onClick={() => setSelectedFileId(file.id)}
                          className={`w-full p-3 rounded-xl border text-left transition-colors cursor-pointer ${
                            active
                              ? 'border-neutral-950 bg-neutral-950 text-white dark:border-white dark:bg-white dark:text-neutral-950'
                              : 'border-neutral-200 dark:border-neutral-800 hover:border-neutral-400 dark:hover:border-neutral-700'
                          }`}
                        >
                          <div className="font-mono text-xs font-semibold truncate">
                            {file.title}
                          </div>
                          <div
                            className={`text-[11px] mt-0.5 truncate ${
                              active
                                ? 'text-neutral-300 dark:text-neutral-600'
                                : 'text-neutral-500'
                            }`}
                          >
                            {file.path}
                          </div>
                        </button>
                      );
                    })}
                  </div>
                </div>

                {/* Folder Structure Reference */}
                <div className="p-5 rounded-2xl border border-neutral-200 dark:border-neutral-800 bg-white dark:bg-neutral-900/40 space-y-3">
                  <div className="flex items-center justify-between">
                    <h3 className="text-xs font-bold flex items-center gap-1.5">
                      <FolderTree className="w-4 h-4" />
                      <span>Flutter Project Structure</span>
                    </h3>
                    <button
                      onClick={() =>
                        handleCopy(FOLDER_STRUCTURE_TREE, 'folder-tree')
                      }
                      className="text-xs font-medium underline cursor-pointer"
                    >
                      {copiedId === 'folder-tree' ? 'Copied' : 'Copy Tree'}
                    </button>
                  </div>
                  <pre className="text-[11px] font-mono text-neutral-700 dark:text-neutral-300 overflow-x-auto leading-relaxed">
                    {FOLDER_STRUCTURE_TREE}
                  </pre>
                </div>
              </div>

              {/* Right Column: Full Source Code Viewer */}
              <div className="lg:col-span-8">
                <div className="rounded-2xl border border-neutral-200 dark:border-neutral-800 bg-white dark:bg-neutral-900/40 overflow-hidden">
                  <div className="px-6 py-4 border-b border-neutral-200 dark:border-neutral-800 flex flex-wrap items-center justify-between gap-4">
                    <div>
                      <div className="font-mono text-sm font-bold">
                        {selectedFile.path}
                      </div>
                      <p className="text-xs text-neutral-500 dark:text-neutral-400 mt-1 max-w-2xl">
                        {selectedFile.summary}
                      </p>
                    </div>
                    <div className="flex items-center gap-2 shrink-0">
                      <button
                        onClick={() =>
                          handleCopy(selectedFile.content, selectedFile.id)
                        }
                        className="px-3.5 py-2 rounded-lg border border-neutral-300 dark:border-neutral-700 text-xs font-semibold flex items-center gap-1.5 hover:bg-neutral-100 dark:hover:bg-neutral-800 transition-colors cursor-pointer"
                      >
                        {copiedId === selectedFile.id ? (
                          <>
                            <Check className="w-3.5 h-3.5" />
                            <span>Copied</span>
                          </>
                        ) : (
                          <>
                            <Copy className="w-3.5 h-3.5" />
                            <span>Copy Code</span>
                          </>
                        )}
                      </button>
                      <button
                        onClick={() => handleDownloadFile(selectedFile)}
                        className="px-3.5 py-2 rounded-lg bg-neutral-950 text-white dark:bg-white dark:text-neutral-950 text-xs font-semibold flex items-center gap-1.5 hover:opacity-90 transition-opacity cursor-pointer"
                      >
                        <Download className="w-3.5 h-3.5" />
                        <span>Download File</span>
                      </button>
                    </div>
                  </div>

                  <div className="p-6 overflow-x-auto bg-neutral-950 text-neutral-100">
                    <pre className="text-xs font-mono leading-relaxed">
                      <code>{selectedFile.content}</code>
                    </pre>
                  </div>
                </div>
              </div>
            </div>
          )}
        </main>
      </div>
    </div>
  );
}
