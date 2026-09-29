import { Component, type ReactNode } from 'react';
import { friendlyError } from '../../lib/auth/AuthContext';
import { ErrorState } from '../ui';

/** Catches render-time failures and shows the readable message — never a code
 *  or a stack trace. */
export class ErrorBoundary extends Component<{ children: ReactNode }, { message: string | null }> {
  state = { message: null as string | null };

  static getDerivedStateFromError(error: unknown) {
    return { message: friendlyError(error) };
  }

  render() {
    if (this.state.message) {
      return (
        <ErrorState
          title="Something went wrong"
          message={this.state.message}
          onRetry={() => this.setState({ message: null })}
        />
      );
    }
    return this.props.children;
  }
}