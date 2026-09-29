import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { AuthProvider } from './lib/auth/AuthContext';
import { BrandingProvider } from './lib/BrandingContext';
import { ToastProvider } from './components/ui';
import { ThemeProvider, applyTheme, readStoredTheme } from './lib/theme';
import { ErrorBoundary } from './components/layout/ErrorBoundary';
import { AppRoutes } from './App';
import './index.css';
import './components/ui/styles.css';
import './components/layout/styles.css';

// No-flash: apply the stored appearance before the first frame renders.
applyTheme(readStoredTheme());

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <ErrorBoundary>
      <BrowserRouter>
        <ThemeProvider>
          <AuthProvider>
            <BrandingProvider>
              <ToastProvider>
                <AppRoutes />
              </ToastProvider>
            </BrandingProvider>
          </AuthProvider>
        </ThemeProvider>
      </BrowserRouter>
    </ErrorBoundary>
  </React.StrictMode>,
);