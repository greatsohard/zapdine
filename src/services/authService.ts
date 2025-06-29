import { supabase } from '@/integrations/supabase/client';
import { AuthResult, Profile } from '@/types/auth';

class AuthService {
  async fetchProfile(userId: string): Promise<Profile | null> {
    try {
      console.log('Fetching profile for user:', userId);
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .single();

      if (error) {
        console.error('Error fetching profile:', error);
        return null;
      }

      console.log('Profile fetched:', data);
      return data;
    } catch (error) {
      console.error('Error fetching profile:', error);
      return null;
    }
  }

  async signUp(email: string, password: string, fullName: string, username: string): Promise<AuthResult> {
    try {
      console.log('Starting signup process...');
      
      // Check if username already exists
      const { data: existingUser, error: checkError } = await supabase
        .from('profiles')
        .select('username')
        .eq('username', username)
        .maybeSingle();

      if (checkError && checkError.code !== 'PGRST116') {
        console.error('Error checking username:', checkError);
        return { error: { message: 'Error checking username availability. Please try again.' } };
      }

      if (existingUser) {
        return { error: { message: 'Username already exists. Please choose a different username.' } };
      }

      const currentDomain = window.location.origin;
      const redirectUrl = `${currentDomain}/auth?message=welcome&email=${encodeURIComponent(email)}`;
      
      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: {
          emailRedirectTo: redirectUrl,
          data: {
            full_name: fullName,
            username: username
          }
        }
      });
      
      if (error) {
        console.error('Signup error:', error);
        let errorMessage = error.message;
        
        // Provide more user-friendly error messages
        if (error.message.includes('User already registered')) {
          errorMessage = 'An account with this email already exists. Please try signing in instead.';
        } else if (error.message.includes('Password should be at least')) {
          errorMessage = 'Password must be at least 6 characters long.';
        } else if (error.message.includes('Invalid email')) {
          errorMessage = 'Please enter a valid email address.';
        }
        
        return { error: { message: errorMessage } };
      }
      
      console.log('Signup successful, user:', data.user?.id);
      return { error: null };
    } catch (error: any) {
      console.error('Signup error:', error);
      return { error: { message: error.message || 'An error occurred during signup' } };
    }
  }

  async signIn(identifier: string, password: string): Promise<AuthResult> {
    try {
      console.log('Attempting sign in with identifier:', identifier);
      
      // Determine if identifier is email or username
      const isEmail = identifier.includes('@');
      
      if (isEmail) {
        // Direct email login
        console.log('Attempting email login');
        const { data, error } = await supabase.auth.signInWithPassword({
          email: identifier,
          password
        });
        
        if (error) {
          console.error('Email login error:', error);
          let errorMessage = 'Invalid email or password. Please check your credentials and try again.';
          
          // Provide more specific error messages
          if (error.message.includes('Email not confirmed')) {
            errorMessage = 'Please check your email and click the confirmation link before signing in.';
          } else if (error.message.includes('Invalid login credentials')) {
            errorMessage = 'Invalid email or password. Please check your credentials and try again.';
          } else if (error.message.includes('Too many requests')) {
            errorMessage = 'Too many login attempts. Please wait a moment before trying again.';
          }
          
          return { error: { message: errorMessage } };
        }
        
        // Check if user has a profile, create one if missing
        if (data.user) {
          await this.ensureProfileExists(data.user);
        }
        
        console.log('Email login successful');
        return { error: null };
      } else {
        // Username login - lookup email first
        console.log('Attempting username login, looking up email');
        const { data: profileData, error: profileError } = await supabase
          .from('profiles')
          .select('email')
          .eq('username', identifier)
          .maybeSingle();
          
        if (profileError && profileError.code !== 'PGRST116') {
          console.error('Username lookup error:', profileError);
          return { error: { message: 'An error occurred while looking up your username. Please try again.' } };
        }
        
        if (!profileData?.email) {
          console.log('Username not found');
          return { error: { message: 'Invalid username or password. Please check your credentials and try again.' } };
        }
        
        console.log('Username found, attempting login with email:', profileData.email);
        const { data, error: loginError } = await supabase.auth.signInWithPassword({
          email: profileData.email,
          password
        });
        
        if (loginError) {
          console.error('Username-based login error:', loginError);
          let errorMessage = 'Invalid username or password. Please check your credentials and try again.';
          
          if (loginError.message.includes('Email not confirmed')) {
            errorMessage = 'Please check your email and click the confirmation link before signing in.';
          } else if (loginError.message.includes('Too many requests')) {
            errorMessage = 'Too many login attempts. Please wait a moment before trying again.';
          }
          
          return { error: { message: errorMessage } };
        }
        
        // Check if user has a profile, create one if missing
        if (data.user) {
          await this.ensureProfileExists(data.user);
        }
        
        console.log('Username login successful');
        return { error: null };
      }
      
    } catch (error: any) {
      console.error('Signin error:', error);
      return { error: { message: error.message || 'An error occurred during signin. Please try again.' } };
    }
  }

  private async ensureProfileExists(user: any): Promise<void> {
    try {
      // Check if profile exists
      const { data: existingProfile, error: fetchError } = await supabase
        .from('profiles')
        .select('id')
        .eq('id', user.id)
        .maybeSingle();

      if (fetchError && fetchError.code !== 'PGRST116') {
        console.error('Error checking profile existence:', fetchError);
        return;
      }

      // If profile doesn't exist, create it
      if (!existingProfile) {
        console.log('Profile not found, creating one for user:', user.id);
        
        const profileData = {
          id: user.id,
          email: user.email,
          full_name: user.user_metadata?.full_name || user.email?.split('@')[0] || '',
          username: user.user_metadata?.username || user.email?.split('@')[0] || '',
          has_restaurant: false
        };

        const { error: insertError } = await supabase
          .from('profiles')
          .insert([profileData]);

        if (insertError) {
          console.error('Error creating profile:', insertError);
        } else {
          console.log('Profile created successfully');
        }
      }
    } catch (error) {
      console.error('Error ensuring profile exists:', error);
    }
  }

  async resetPassword(email: string): Promise<AuthResult> {
    try {
      const currentDomain = window.location.origin;
      const redirectUrl = `${currentDomain}/auth?message=reset`;
      
      const { error } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: redirectUrl
      });
      
      if (error) {
        let errorMessage = error.message;
        
        if (error.message.includes('For security purposes')) {
          errorMessage = 'For security purposes, you can only request a password reset every 60 seconds.';
        } else if (error.message.includes('Unable to validate email address')) {
          errorMessage = 'Please enter a valid email address.';
        }
        
        return { error: { message: errorMessage } };
      }
      
      return { error: null };
    } catch (error: any) {
      console.error('Reset password error:', error);
      return { error: { message: error.message || 'An error occurred during password reset' } };
    }
  }

  async signOut(): Promise<void> {
    await supabase.auth.signOut();
    window.location.href = '/';
  }
}

// Export a single instance to maintain consistent context
export const authService = new AuthService();