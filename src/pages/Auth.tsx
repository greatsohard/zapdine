import { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/components/ui/use-toast';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { CheckCircle, Mail, User, ArrowLeft, Eye, EyeOff, AlertCircle } from 'lucide-react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';

const Auth = () => {
  const [isLogin, setIsLogin] = useState(true);
  const [isForgotPassword, setIsForgotPassword] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [fullName, setFullName] = useState('');
  const [username, setUsername] = useState('');
  const [identifier, setIdentifier] = useState('');
  const [loading, setLoading] = useState(false);
  const [showEmailSent, setShowEmailSent] = useState(false);
  const [showResetSent, setShowResetSent] = useState(false);
  const [loginType, setLoginType] = useState<'email' | 'username'>('email');
  const [searchParams] = useSearchParams();
  const { signIn, signUp, resetPassword, user } = useAuth();
  const navigate = useNavigate();

  const welcomeMessage = searchParams.get('message') === 'welcome';
  const resetMessage = searchParams.get('message') === 'reset';
  const userEmail = searchParams.get('email');

  useEffect(() => {
    if (user) {
      navigate('/dashboard');
    }
  }, [user, navigate]);

  const validateForm = () => {
    if (!isLogin && !isForgotPassword) {
      // Sign up validation
      if (!fullName.trim()) {
        toast({
          title: "Error",
          description: "Please enter your full name",
          variant: "destructive"
        });
        return false;
      }
      if (!username.trim()) {
        toast({
          title: "Error",
          description: "Please enter a username",
          variant: "destructive"
        });
        return false;
      }
      if (username.trim().length < 3) {
        toast({
          title: "Error",
          description: "Username must be at least 3 characters long",
          variant: "destructive"
        });
        return false;
      }
      if (!/^[a-zA-Z0-9_]+$/.test(username.trim())) {
        toast({
          title: "Error",
          description: "Username can only contain letters, numbers, and underscores",
          variant: "destructive"
        });
        return false;
      }
      if (!email.trim()) {
        toast({
          title: "Error",
          description: "Please enter your email address",
          variant: "destructive"
        });
        return false;
      }
      if (password.length < 6) {
        toast({
          title: "Error",
          description: "Password must be at least 6 characters long",
          variant: "destructive"
        });
        return false;
      }
    } else if (isLogin && !isForgotPassword) {
      // Sign in validation
      if (!identifier.trim()) {
        toast({
          title: "Error",
          description: `Please enter your ${loginType === 'email' ? 'email address' : 'username'}`,
          variant: "destructive"
        });
        return false;
      }
      if (!password.trim()) {
        toast({
          title: "Error",
          description: "Please enter your password",
          variant: "destructive"
        });
        return false;
      }
    } else if (isForgotPassword) {
      // Password reset validation
      if (!email.trim()) {
        toast({
          title: "Error",
          description: "Please enter your email address",
          variant: "destructive"
        });
        return false;
      }
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
        toast({
          title: "Error",
          description: "Please enter a valid email address",
          variant: "destructive"
        });
        return false;
      }
    }
    return true;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!validateForm()) {
      return;
    }
    
    setLoading(true);

    try {
      if (isForgotPassword) {
        const { error } = await resetPassword(email.trim());
        if (error) {
          toast({
            title: "Reset Failed",
            description: error.message,
            variant: "destructive"
          });
        } else {
          setShowResetSent(true);
          setEmail('');
        }
      } else if (isLogin) {
        const result = await signIn(identifier.trim(), password);
        
        if (result.error) {
          toast({
            title: "Login Failed",
            description: result.error.message,
            variant: "destructive"
          });
        } else {
          toast({
            title: "Welcome back!",
            description: "You have successfully logged in.",
          });
          navigate('/dashboard');
        }
      } else {
        // Sign up
        console.log('Submitting signup');
        const { error } = await signUp(email.trim(), password, fullName.trim(), username.trim());
        if (error) {
          console.error('Signup failed:', error);
          toast({
            title: "Signup Failed",
            description: error.message,
            variant: "destructive"
          });
        } else {
          setShowEmailSent(true);
          setEmail('');
          setPassword('');
          setFullName('');
          setUsername('');
        }
      }
    } catch (error: any) {
      console.error('Auth error:', error);
      toast({
        title: "Error",
        description: error.message || "An unexpected error occurred",
        variant: "destructive"
      });
    } finally {
      setLoading(false);
    }
  };

  const resetForm = () => {
    setIsLogin(true);
    setIsForgotPassword(false);
    setShowEmailSent(false);
    setShowResetSent(false);
    setEmail('');
    setPassword('');
    setShowPassword(false);
    setFullName('');
    setUsername('');
    setIdentifier('');
  };

  const togglePasswordVisibility = () => {
    setShowPassword(!showPassword);
  };

  if (showEmailSent) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-amber-50 to-orange-50 flex items-center justify-center px-4">
        <div className="w-full max-w-md">
          <div className="text-center mb-8">
            <div className="w-16 h-16 bg-amber-500 rounded-full flex items-center justify-center mx-auto mb-4">
              <Mail className="text-2xl text-white w-8 h-8" />
            </div>
            <h1 className="text-3xl font-bold text-amber-600">Check Your Email</h1>
          </div>

          <Card className="border-amber-100">
            <CardContent className="p-6 text-center">
              <CheckCircle className="w-12 h-12 text-green-500 mx-auto mb-4" />
              <h3 className="text-lg font-semibold text-gray-900 mb-2">
                Welcome to ZapDine!
              </h3>
              <p className="text-gray-600 mb-4">
                We've sent you a beautiful confirmation email with a warm welcome message. 
                Please check your inbox and click the confirmation link to activate your account.
              </p>
              <Alert className="mb-4 border-green-200 bg-green-50">
                <CheckCircle className="h-4 w-4 text-green-600" />
                <AlertDescription className="text-green-800">
                  🎉 Your 14-day free trial starts now! After confirming your email, you'll have full access to all features.
                </AlertDescription>
              </Alert>
              <Button
                onClick={resetForm}
                className="w-full bg-amber-500 hover:bg-amber-600"
              >
                Back to Login
              </Button>
            </CardContent>
          </Card>

          <footer className="mt-8 text-center">
            <p className="text-gray-600">
              Powered by <a href="https://spslabs.vercel.app" target="_blank" rel="noopener noreferrer" className="font-semibold text-amber-600 hover:underline">SPS Labs</a>
            </p>
          </footer>
        </div>
      </div>
    );
  }

  if (showResetSent) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-amber-50 to-orange-50 flex items-center justify-center px-4">
        <div className="w-full max-w-md">
          <div className="text-center mb-8">
            <div className="w-16 h-16 bg-amber-500 rounded-full flex items-center justify-center mx-auto mb-4">
              <Mail className="text-2xl text-white w-8 h-8" />
            </div>
            <h1 className="text-3xl font-bold text-amber-600">Reset Email Sent</h1>
          </div>

          <Card className="border-amber-100">
            <CardContent className="p-6 text-center">
              <CheckCircle className="w-12 h-12 text-green-500 mx-auto mb-4" />
              <h3 className="text-lg font-semibold text-gray-900 mb-2">
                Password Reset Instructions Sent
              </h3>
              <p className="text-gray-600 mb-4">
                We've sent beautiful password reset instructions to your email. 
                Please check your inbox and follow the link to reset your password.
              </p>
              <Button
                onClick={resetForm}
                className="w-full bg-amber-500 hover:bg-amber-600"
              >
                Back to Login
              </Button>
            </CardContent>
          </Card>

          <footer className="mt-8 text-center">
            <p className="text-gray-600">
              Powered by <a href="https://spslabs.vercel.app" target="_blank" rel="noopener noreferrer" className="font-semibold text-amber-600 hover:underline">SPS Labs</a>
            </p>
          </footer>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-amber-50 to-orange-50 flex items-center justify-center px-4">
      <div className="w-full max-w-md">
        {/* Header */}
        <div className="text-center mb-8">
          <div className="w-16 h-16 bg-amber-500 rounded-full flex items-center justify-center mx-auto mb-4">
            <span className="text-2xl font-bold text-white">Z</span>
          </div>
          <h1 className="text-3xl font-bold text-amber-600">ZapDine</h1>
          <p className="text-gray-600 mt-2">Restaurant Management Made Simple</p>
        </div>

        {/* Welcome/Reset Messages */}
        {welcomeMessage && (
          <Alert className="mb-6 border-green-200 bg-green-50">
            <CheckCircle className="h-4 w-4 text-green-600" />
            <AlertDescription className="text-green-800">
              🎉 Welcome to ZapDine{userEmail ? `, ${userEmail.split('@')[0]}` : ''}! 
              Your account has been confirmed successfully. Your 14-day free trial has started!
            </AlertDescription>
          </Alert>
        )}

        {resetMessage && (
          <Alert className="mb-6 border-blue-200 bg-blue-50">
            <CheckCircle className="h-4 w-4 text-blue-600" />
            <AlertDescription className="text-blue-800">
              You can now reset your password using the form below.
            </AlertDescription>
          </Alert>
        )}

        {/* Demo Account Info */}
        {isLogin && !isForgotPassword && (
          <Alert className="mb-6 border-blue-200 bg-blue-50">
            <AlertCircle className="h-4 w-4 text-blue-600" />
            <AlertDescription className="text-blue-800">
              <strong>Demo Account:</strong><br />
              Email: demo@zapdine.com<br />
              Password: demo123<br />
              <em>Or create your own account below!</em>
            </AlertDescription>
          </Alert>
        )}

        <Card className="border-amber-100 shadow-lg">
          <CardHeader>
            <div className="flex items-center gap-2">
              {isForgotPassword && (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setIsForgotPassword(false)}
                  className="p-1"
                >
                  <ArrowLeft className="w-4 h-4" />
                </Button>
              )}
              <CardTitle className="text-center text-amber-600 flex-1">
                {isForgotPassword 
                  ? 'Reset Your Password'
                  : isLogin 
                    ? 'Sign In to Your Account' 
                    : 'Create Your ZapDine Account'
                }
              </CardTitle>
            </div>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleSubmit} className="space-y-4">
              {isForgotPassword ? (
                <div className="space-y-2">
                  <Label htmlFor="reset-email">Email Address</Label>
                  <Input
                    id="reset-email"
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="Enter your email"
                    required
                    className="focus:border-amber-500 focus:ring-amber-500"
                  />
                </div>
              ) : (
                <>
                  {!isLogin && (
                    <>
                      <div className="space-y-2">
                        <Label htmlFor="fullName">Full Name *</Label>
                        <Input
                          id="fullName"
                          type="text"
                          value={fullName}
                          onChange={(e) => setFullName(e.target.value)}
                          placeholder="Enter your full name"
                          required
                          className="focus:border-amber-500 focus:ring-amber-500"
                        />
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="username">Username *</Label>
                        <Input
                          id="username"
                          type="text"
                          value={username}
                          onChange={(e) => setUsername(e.target.value)}
                          placeholder="Choose a username (letters, numbers, underscore only)"
                          required
                          className="focus:border-amber-500 focus:ring-amber-500"
                          minLength={3}
                          pattern="[a-zA-Z0-9_]+"
                        />
                        <p className="text-xs text-gray-500">At least 3 characters, letters, numbers and underscore only</p>
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="email">Email Address *</Label>
                        <Input
                          id="email"
                          type="email"
                          value={email}
                          onChange={(e) => setEmail(e.target.value)}
                          placeholder="Enter your email"
                          required
                          className="focus:border-amber-500 focus:ring-amber-500"
                        />
                      </div>
                    </>
                  )}
                  
                  {isLogin && (
                    <>
                      <Tabs value={loginType} onValueChange={(value) => setLoginType(value as typeof loginType)} className="w-full">
                        <TabsList className="grid w-full grid-cols-2">
                          <TabsTrigger value="email" className="flex items-center gap-1">
                            <Mail className="w-4 h-4" />
                            Email
                          </TabsTrigger>
                          <TabsTrigger value="username" className="flex items-center gap-1">
                            <User className="w-4 h-4" />
                            Username
                          </TabsTrigger>
                        </TabsList>
                        <TabsContent value="email" className="space-y-2 mt-4">
                          <Label htmlFor="identifier">Email Address</Label>
                          <Input
                            id="identifier"
                            type="email"
                            value={identifier}
                            onChange={(e) => setIdentifier(e.target.value)}
                            placeholder="Enter your email"
                            required
                            className="focus:border-amber-500 focus:ring-amber-500"
                          />
                        </TabsContent>
                        <TabsContent value="username" className="space-y-2 mt-4">
                          <Label htmlFor="identifier">Username</Label>
                          <Input
                            id="identifier"
                            type="text"
                            value={identifier}
                            onChange={(e) => setIdentifier(e.target.value)}
                            placeholder="Enter your username"
                            required
                            className="focus:border-amber-500 focus:ring-amber-500"
                          />
                        </TabsContent>
                      </Tabs>
                    </>
                  )}
                  
                  <div className="space-y-2">
                    <Label htmlFor="password">Password</Label>
                    <div className="relative">
                      <Input
                        id="password"
                        type={showPassword ? "text" : "password"}
                        value={password}
                        onChange={(e) => setPassword(e.target.value)}
                        placeholder="Enter your password"
                        required
                        className="focus:border-amber-500 focus:ring-amber-500 pr-10"
                        minLength={6}
                      />
                      <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        className="absolute right-0 top-0 h-full px-3 py-2 hover:bg-transparent"
                        onClick={togglePasswordVisibility}
                      >
                        {showPassword ? (
                          <EyeOff className="h-4 w-4 text-gray-400" />
                        ) : (
                          <Eye className="h-4 w-4 text-gray-400" />
                        )}
                      </Button>
                    </div>
                    {!isLogin && (
                      <p className="text-xs text-gray-500">Password must be at least 6 characters long</p>
                    )}
                  </div>
                </>
              )}
              
              <Button
                type="submit"
                disabled={loading}
                className="w-full bg-amber-500 hover:bg-amber-600 transition-colors"
              >
                {loading ? 'Please wait...' : (
                  isForgotPassword ? 'Send Reset Email' :
                  isLogin ? 'Sign In' : 'Create Account'
                )}
              </Button>
            </form>
            
            {isLogin && !isForgotPassword && (
              <div className="mt-4 text-center">
                <button
                  type="button"
                  onClick={() => setIsForgotPassword(true)}
                  className="text-amber-600 hover:text-amber-700 text-sm font-medium transition-colors"
                >
                  Forgot your password?
                </button>
              </div>
            )}
            
            {!isForgotPassword && (
              <div className="mt-6 text-center">
                <button
                  type="button"
                  onClick={() => {
                    setIsLogin(!isLogin);
                    setEmail('');
                    setPassword('');
                    setShowPassword(false);
                    setFullName('');
                    setUsername('');
                    setIdentifier('');
                  }}
                  className="text-amber-600 hover:text-amber-700 text-sm font-medium transition-colors"
                >
                  {isLogin 
                    ? "Don't have an account? Create one now" 
                    : "Already have an account? Sign in instead"
                  }
                </button>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Footer */}
        <footer className="mt-8 text-center">
          <p className="text-gray-600">
            Powered by <a href="https://spslabs.vercel.app" target="_blank" rel="noopener noreferrer" className="font-semibold text-amber-600 hover:underline">SPS Labs</a>
          </p>
        </footer>
      </div>
    </div>
  );
};

export default Auth;